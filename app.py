from __future__ import annotations

import json
import math
import os
import re
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from io import BytesIO
from datetime import datetime, timezone
from pathlib import Path
import tempfile

import faiss  # type: ignore[import-not-found]
import numpy as np
import streamlit as st
from PIL import Image, ImageEnhance, ImageOps


st.set_page_config(page_title="Atlas Vision", page_icon="AV", layout="wide")

st.markdown(
    """
    <style>
    @import url('https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Space+Grotesk:wght@400;500;600;700&display=swap');
    :root { --ink:#17211e; --paper:#f4f1e9; --lime:#d9ee67; --coral:#e96b50; --muted:#65736d; --line:#c6c9bc; }
    .stApp { background:var(--paper); color:var(--ink); }
    .block-container { max-width:980px; padding:2.5rem 2rem 4rem; }
    h1,h2,h3,p,div,button,label { font-family:'Space Grotesk',sans-serif; }
    h1 { font-size:clamp(2.8rem,5.6vw,5.4rem); line-height:.92; letter-spacing:-.06em; margin:0; max-width:11ch; }
    h2 { letter-spacing:-.045em; }
    .mono { font-family:'DM Mono',monospace; text-transform:uppercase; letter-spacing:.1em; font-size:.7rem; }
    .eyebrow { color:var(--coral); margin-bottom:1rem; }
    .lede { max-width:34rem; color:var(--muted); font-size:1rem; line-height:1.5; margin-top:1.2rem; }
    .panel { border:1px solid var(--line); background:#faf9f4; padding:1.2rem; min-height:11rem; }
    .panel h3 { margin:.4rem 0; font-size:1.25rem; }
    .panel p { color:var(--muted); line-height:1.45; margin:0; }
    .stat { border-top:2px solid var(--ink); padding-top:.55rem; }
    .stat strong { display:block; font-size:1.8rem; letter-spacing:-.04em; }
    .stButton > button, .stDownloadButton > button { border:1px solid var(--ink); border-radius:0; background:var(--lime); color:var(--ink); font-weight:700; min-height:2.7rem; }
    .stButton > button:hover, .stDownloadButton > button:hover { border-color:var(--coral); color:var(--ink); }
    [data-testid='stFileUploader'] { border:1px dashed var(--ink); background:#e8ebdf; padding:1.25rem; }
    [data-baseweb='tab-list'] { gap:.6rem; border-bottom:1px solid var(--line); }
    [data-baseweb='tab'] { font-family:'DM Mono',monospace; text-transform:uppercase; letter-spacing:.08em; }
    .note { border-left:3px solid var(--coral); padding:.7rem 1rem; background:#eeeade; color:var(--muted); line-height:1.45; }
    .result-title { font-size:clamp(2rem,4vw,3.8rem); letter-spacing:-.05em; line-height:1; margin:.2rem 0 .7rem; }
    .result-address { color:var(--muted); line-height:1.45; margin-bottom:1.2rem; }
    .mode-caption { color:var(--muted); font-size:.9rem; margin:0 0 1.5rem; }
    @media (max-width: 640px) { .block-container { padding:1.25rem 1rem 3rem; } h1 { font-size:3.2rem; } }
    </style>
    """,
    unsafe_allow_html=True,
)


COORDINATE_PATTERN = re.compile(
    r"(?<!\d)(-?\d{1,3}(?:\.\d+)?)[_ ,;]+(-?\d{1,3}(?:\.\d+)?)(?!\d)"
)
IMAGE_TYPES = ["jpg", "jpeg", "png", "webp"]
DATA_DIR = Path("data")
INDEX_PATH = DATA_DIR / "atlas.index"
METADATA_PATH = DATA_DIR / "atlas.json"
EVENTS_PATH = DATA_DIR / "events.jsonl"


@dataclass
class Sample:
    name: str
    latitude: float
    longitude: float
    vector: list[float]


def parse_coordinates(filename: str) -> tuple[float, float] | None:
    stem = filename.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    for match in COORDINATE_PATTERN.finditer(stem):
        latitude, longitude = map(float, match.groups())
        if -90 <= latitude <= 90 and -180 <= longitude <= 180:
            return latitude, longitude
    return None


def _histogram(values: np.ndarray, bins: int) -> np.ndarray:
    histogram, _ = np.histogram(values, bins=bins, range=(0.0, 1.0))
    return histogram.astype(np.float32) / max(1, values.size)


def _single_view_vector(image: Image.Image) -> np.ndarray:
    rgb = ImageOps.fit(image, (96, 96), method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
    pixels = np.asarray(rgb, dtype=np.float32) / 255.0
    gray = pixels.mean(axis=2)
    features: list[np.ndarray] = []
    for grid in (1, 2, 4):
        for row in np.array_split(pixels, grid, axis=0):
            for cell in np.array_split(row, grid, axis=1):
                features.extend((cell.mean(axis=(0, 1)), cell.std(axis=(0, 1))))
    features.extend((_histogram(pixels[:, :, 0], 12), _histogram(pixels[:, :, 1], 12), _histogram(pixels[:, :, 2], 12)))
    horizontal = np.abs(np.diff(gray, axis=1)).ravel()
    vertical = np.abs(np.diff(gray, axis=0)).ravel()
    features.extend((_histogram(horizontal, 12), _histogram(vertical, 12)))
    features.extend((np.array([gray.mean(), gray.std(), np.mean(horizontal), np.mean(vertical)], dtype=np.float32),))
    pixel_grid = ImageOps.fit(rgb, (16, 16), method=Image.Resampling.LANCZOS)
    pixel_features = np.asarray(pixel_grid, dtype=np.float32).ravel() / 255.0
    pixel_features /= max(np.linalg.norm(pixel_features), 1e-8)
    features.append(pixel_features * 1.25)
    micro_gray = np.asarray(ImageOps.grayscale(ImageOps.fit(rgb, (24, 24), method=Image.Resampling.LANCZOS)), dtype=np.float32) / 255.0
    micro_gray -= micro_gray.mean()
    micro_gray /= max(np.linalg.norm(micro_gray), 1e-8)
    micro_horizontal = np.diff(micro_gray, axis=1).ravel()
    micro_vertical = np.diff(micro_gray, axis=0).ravel()
    features.extend((micro_gray.ravel() * 1.5, micro_horizontal * 1.1, micro_vertical * 1.1))
    vector = np.concatenate([np.asarray(item, dtype=np.float32).ravel() for item in features])
    norm = np.linalg.norm(vector)
    return vector / norm if norm else vector


def _views(image: Image.Image) -> list[Image.Image]:
    """Build cheap test-time augmentations for small images and mild viewpoint changes."""
    base = ImageOps.exif_transpose(image).convert("RGB")
    width, height = base.size
    crop_ratio = 0.96 if min(width, height) >= 48 else 0.98
    left = int(width * (1 - crop_ratio) / 2)
    top = int(height * (1 - crop_ratio) / 2)
    crop = base.crop((left, top, width - left, height - top))
    return [
        base,
        ImageOps.mirror(base),
        crop,
        base.rotate(-4, resample=Image.Resampling.BILINEAR, expand=False),
        base.rotate(4, resample=Image.Resampling.BILINEAR, expand=False),
        ImageEnhance.Brightness(base).enhance(0.82),
        ImageEnhance.Brightness(base).enhance(1.18),
        ImageEnhance.Contrast(base).enhance(0.82),
        ImageEnhance.Contrast(base).enhance(1.18),
    ]


def visual_vector(image: Image.Image) -> np.ndarray:
    """Create a multi-view descriptor without pretrained models."""
    vectors = np.asarray([_single_view_vector(view) for view in _views(image)], dtype=np.float32)
    weights = np.asarray([4.0, 0.75, 1.5, 0.75, 0.75, 0.5, 0.5, 0.5, 0.5], dtype=np.float32)
    vector = np.average(vectors, axis=0, weights=weights)
    norm = np.linalg.norm(vector)
    return vector / norm if norm else vector


def _new_index(dimension: int) -> faiss.Index:
    return faiss.IndexFlatL2(dimension)


def _write_json_atomic(path: Path, payload: object) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=DATA_DIR, delete=False) as temporary:
        json.dump(payload, temporary, indent=2)
        temporary.write("\n")
        temporary_path = temporary.name
    os.replace(temporary_path, path)


def persist_atlas(index: faiss.Index, samples: list[Sample]) -> None:
    """Write a complete new snapshot, then atomically replace each current file."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    _write_json_atomic(
        METADATA_PATH,
        {"format": "atlas-vision-faiss-v1", "feature_version": 4, "samples": [asdict(sample) for sample in samples]},
    )
    with tempfile.NamedTemporaryFile("wb", dir=DATA_DIR, delete=False) as temporary:
        index_path = temporary.name
    try:
        faiss.write_index(index, index_path)
        os.replace(index_path, INDEX_PATH)
    finally:
        if os.path.exists(index_path):
            os.unlink(index_path)


def load_atlas() -> tuple[faiss.Index | None, list[Sample]]:
    if not METADATA_PATH.exists():
        return None, []
    payload = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    if payload.get("format") != "atlas-vision-faiss-v1":
        raise ValueError("Format atlas tersimpan tidak dikenali")
    samples = [Sample(**item) for item in payload.get("samples", [])]
    if not samples:
        return None, []
    try:
        index = faiss.read_index(str(INDEX_PATH)) if INDEX_PATH.exists() else None
    except RuntimeError:
        index = None
    dimension = len(samples[0].vector)
    if index is None or index.ntotal != len(samples) or index.d != dimension:
        index = _new_index(dimension)
        index.add(np.asarray([sample.vector for sample in samples], dtype=np.float32))
        persist_atlas(index, samples)
    return index, samples


def append_atlas(new_samples: list[Sample]) -> tuple[faiss.Index | None, list[Sample], int]:
    index, samples = load_atlas()
    known = {(sample.name, sample.latitude, sample.longitude) for sample in samples}
    fresh = [sample for sample in new_samples if (sample.name, sample.latitude, sample.longitude) not in known]
    if not fresh:
        return index, samples, 0
    if index is None:
        index = _new_index(len(fresh[0].vector))
    index.add(np.asarray([sample.vector for sample in fresh], dtype=np.float32))
    samples.extend(fresh)
    persist_atlas(index, samples)
    return index, samples, len(fresh)


def log_event(kind: str, **details: object) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    event = {"time": datetime.now(timezone.utc).isoformat(), "kind": kind, **details}
    with EVENTS_PATH.open("a", encoding="utf-8") as events:
        events.write(json.dumps(event) + "\n")


def read_events() -> list[dict[str, object]]:
    if not EVENTS_PATH.exists():
        return []
    return [json.loads(line) for line in EVENTS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]


@st.cache_data(ttl=86400, show_spinner=False)
def reverse_geocode(latitude: float, longitude: float) -> dict[str, str]:
    query = urllib.parse.urlencode({"lat": f"{latitude:.6f}", "lon": f"{longitude:.6f}", "format": "jsonv2", "zoom": 10})
    request = urllib.request.Request(
        f"https://nominatim.openstreetmap.org/reverse?{query}",
        headers={"User-Agent": "AtlasVision/1.0 (local visual geolocation app)"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.load(response)
    except (OSError, json.JSONDecodeError):
        return {"city": "Tidak tersedia", "country": "Tidak tersedia", "display_name": "Reverse geocoding gagal"}
    address = payload.get("address", {})
    city = address.get("city") or address.get("town") or address.get("village") or address.get("municipality") or "Tidak tersedia"
    country = address.get("country") or "Tidak tersedia"
    return {"city": city, "country": country, "display_name": payload.get("display_name", f"{latitude:.6f}, {longitude:.6f}")}


def map_links(latitude: float, longitude: float) -> tuple[str, str]:
    coordinate = f"{latitude:.6f},{longitude:.6f}"
    return (
        f"https://www.google.com/maps/search/?api=1&query={urllib.parse.quote(coordinate)}",
        f"https://www.openstreetmap.org/?mlat={latitude:.6f}&mlon={longitude:.6f}#map=15/{latitude:.6f}/{longitude:.6f}",
    )


def haversine_km(first: tuple[float, float], second: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*first, *second))
    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(a))


def predict(vector: np.ndarray, samples: list[Sample], index: faiss.Index | None = None) -> tuple[float, float, float, list[tuple[Sample, float]]]:
    if not samples:
        raise ValueError("Atlas belum memiliki sample")
    if index is not None and index.d != vector.size:
        raise ValueError("Dimensi fitur query berbeda dari atlas; rebuild atlas diperlukan")
    if index is not None:
        distances_raw, order_raw = index.search(vector.reshape(1, -1).astype(np.float32), 1)
        order = order_raw[0]
        distances = np.sqrt(np.maximum(distances_raw[0], 0.0))
    else:
        matrix = np.asarray([sample.vector for sample in samples], dtype=np.float32)
        all_distances = np.linalg.norm(matrix - vector, axis=1)
        order = np.argsort(all_distances)[:1]
        distances = all_distances[order]
    winner = int(order[0])
    latitude = samples[winner].latitude
    longitude = samples[winner].longitude
    spread = 0.0
    return latitude, longitude, spread, [(samples[item], float(distance)) for item, distance in zip(order, distances)]


def confidence_score(matches: list[tuple[Sample, float]], spread_km: float) -> float:
    """Heuristic quality signal, deliberately not a probability."""
    if not matches:
        return 0.0
    nearest = matches[0][1]
    visual_signal = max(0.0, min(1.0, 1.0 - nearest))
    geographic_signal = max(0.0, min(1.0, 1.0 - spread_km / 500.0))
    return round(100.0 * (0.75 * visual_signal + 0.25 * geographic_signal), 1)


def evaluate(samples: list[Sample]) -> tuple[float, int]:
    if len(samples) < 2:
        return 0.0, 0
    errors = []
    for held_out, sample in enumerate(samples):
        pool = samples[:held_out] + samples[held_out + 1 :]
        prediction = predict(np.asarray(sample.vector), pool)
        errors.append(haversine_km((sample.latitude, sample.longitude), prediction[:2]))
    return float(np.mean(errors)), len(errors)


def image_bytes(upload) -> Image.Image:
    return Image.open(BytesIO(upload.getvalue()))


def export_model(samples: list[Sample]) -> bytes:
    return json.dumps({"format": "atlas-vision-v1", "samples": [asdict(sample) for sample in samples]}, indent=2).encode()


def import_model(upload) -> list[Sample]:
    payload = json.loads(upload.getvalue().decode("utf-8"))
    if payload.get("format") != "atlas-vision-v1":
        raise ValueError("Format model tidak dikenali")
    return [Sample(**item) for item in payload["samples"]]


if "samples" not in st.session_state or "atlas_index" not in st.session_state:
    st.session_state.atlas_index, st.session_state.samples = load_atlas()
if "train_upload_version" not in st.session_state:
    st.session_state.train_upload_version = 0

st.markdown('<div class="mono eyebrow">ATLAS VISION / PRIVATE GEOSPATIAL SEARCH</div>', unsafe_allow_html=True)
st.title("Find where this was taken.")
st.markdown("<p class='lede'>Drop a photo to get a visual location estimate, city context, and a map you can open immediately.</p>", unsafe_allow_html=True)

locate_tab, train_tab = st.tabs(["LOCATE", "TRAIN"])

with train_tab:
    st.subheader("Teach the visual atlas")
    st.markdown("<p class='mode-caption'>Upload photos whose filenames contain latitude and longitude.</p>", unsafe_allow_html=True)
    uploads = st.file_uploader(
        "Foto training berlabel koordinat",
        type=IMAGE_TYPES,
        accept_multiple_files=True,
        key=f"train_uploads_{st.session_state.train_upload_version}",
    )
    if uploads:
        valid, invalid = [], []
        for upload in uploads:
            if parse_coordinates(upload.name) is None:
                invalid.append(upload.name)
            else:
                valid.append(upload)
        if invalid:
            st.warning("Nama file tanpa koordinat: " + ", ".join(invalid[:8]))
        if st.button("Train / add to atlas", type="primary", disabled=not valid):
            progress = st.progress(0)
            batch = []
            for position, upload in enumerate(valid, start=1):
                latitude, longitude = parse_coordinates(upload.name)  # type: ignore[misc]
                image = image_bytes(upload)
                batch.append(Sample(upload.name, latitude, longitude, visual_vector(image).tolist()))
                progress.progress(position / len(valid))
            st.session_state.atlas_index, st.session_state.samples, added = append_atlas(batch)
            log_event("train", uploaded=len(valid), added=added)
            st.success("Atlas updated.")
            st.session_state.train_upload_version += 1
            st.rerun()
    else:
        st.info("Upload labeled photos to start training.")

with locate_tab:
    st.subheader("Locate a photo")
    st.markdown("<p class='mode-caption'>The image is compared against the trained visual atlas.</p>", unsafe_allow_html=True)
    query = st.file_uploader("Foto yang ingin diprediksi", type=IMAGE_TYPES, accept_multiple_files=False, key="query_upload")
    if query and st.session_state.samples:
        image = image_bytes(query)
        latitude, longitude, spread, matches = predict(visual_vector(image), st.session_state.samples, st.session_state.atlas_index)
        confidence = confidence_score(matches, spread)
        location = reverse_geocode(latitude, longitude)
        google_maps_url, openstreetmap_url = map_links(latitude, longitude)
        log_event("locate", file=query.name, latitude=latitude, longitude=longitude, spread_km=spread)
        left, right = st.columns([0.95, 1.05], gap="large")
        with left:
            st.image(image, caption=query.name, width="stretch")
        with right:
            st.markdown(f"<div class='result-title'>{location['city']}, {location['country']}</div>", unsafe_allow_html=True)
            st.markdown(f"<div class='result-address'>{location['display_name']}</div>", unsafe_allow_html=True)
            st.metric("Estimated latitude", f"{latitude:.6f}")
            st.metric("Estimated longitude", f"{longitude:.6f}")
            map_left, map_right = st.columns(2)
            with map_left:
                st.link_button("Google Maps", google_maps_url, use_container_width=True)
            with map_right:
                st.link_button("OpenStreetMap", openstreetmap_url, use_container_width=True)
            st.caption(f"Visual confidence: {confidence:.1f}/100")
        st.map({"latitude": [latitude], "longitude": [longitude]}, latitude="latitude", longitude="longitude", zoom=10)
    elif not st.session_state.samples:
        st.info("Train atlas terlebih dahulu.")

st.markdown("<p class='mono' style='margin-top:3rem;color:#65736d'>PRIVATE VISUAL SEARCH / OPEN MAP CONTEXT</p>", unsafe_allow_html=True)