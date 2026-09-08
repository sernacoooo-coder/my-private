from __future__ import annotations

import json
import math
import os
import re
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
    .block-container { max-width:1120px; padding:2.5rem 2rem 4rem; }
    h1,h2,h3,p,div,button,label { font-family:'Space Grotesk',sans-serif; }
    h1 { font-size:clamp(3.2rem,7vw,6.8rem); line-height:.9; letter-spacing:-.07em; margin:0; }
    h2 { letter-spacing:-.045em; }
    .mono { font-family:'DM Mono',monospace; text-transform:uppercase; letter-spacing:.1em; font-size:.7rem; }
    .eyebrow { color:var(--coral); margin-bottom:1rem; }
    .lede { max-width:48rem; color:var(--muted); font-size:1.08rem; line-height:1.5; margin-top:1.4rem; }
    .panel { border:1px solid var(--line); background:#faf9f4; padding:1.2rem; min-height:11rem; }
    .panel h3 { margin:.4rem 0; font-size:1.25rem; }
    .panel p { color:var(--muted); line-height:1.45; margin:0; }
    .stat { border-top:2px solid var(--ink); padding-top:.55rem; }
    .stat strong { display:block; font-size:1.8rem; letter-spacing:-.04em; }
    .stButton > button, .stDownloadButton > button { border:1px solid var(--ink); border-radius:0; background:var(--lime); color:var(--ink); font-weight:700; min-height:2.7rem; }
    .stButton > button:hover, .stDownloadButton > button:hover { border-color:var(--coral); color:var(--ink); }
    [data-testid='stFileUploader'] { border:1px dashed var(--ink); background:#e8ebdf; padding:.8rem; }
    [data-baseweb='tab-list'] { gap:.6rem; border-bottom:1px solid var(--line); }
    [data-baseweb='tab'] { font-family:'DM Mono',monospace; text-transform:uppercase; letter-spacing:.08em; }
    .note { border-left:3px solid var(--coral); padding:.7rem 1rem; background:#eeeade; color:var(--muted); line-height:1.45; }
    @media (max-width: 640px) { .block-container { padding:1.5rem 1rem 3rem; } h1 { font-size:3.4rem; } }
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
    rgb = ImageOps.fit(image, (96, 96), method=Image.Resampling.BILINEAR, centering=(0.5, 0.5))
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
    vector = np.concatenate([np.asarray(item, dtype=np.float32).ravel() for item in features])
    norm = np.linalg.norm(vector)
    return vector / norm if norm else vector


def _views(image: Image.Image) -> list[Image.Image]:
    """Build cheap test-time augmentations for small images and mild viewpoint changes."""
    base = ImageOps.exif_transpose(image).convert("RGB")
    width, height = base.size
    crop_ratio = 0.90 if min(width, height) >= 48 else 0.98
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
    vector = vectors.mean(axis=0)
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
        {"format": "atlas-vision-faiss-v1", "feature_version": 2, "samples": [asdict(sample) for sample in samples]},
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


def haversine_km(first: tuple[float, float], second: tuple[float, float]) -> float:
    lat1, lon1, lat2, lon2 = map(math.radians, (*first, *second))
    a = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(a))


def predict(vector: np.ndarray, samples: list[Sample], index: faiss.Index | None = None, neighbours: int = 5) -> tuple[float, float, float, list[tuple[Sample, float]]]:
    if not samples:
        raise ValueError("Atlas belum memiliki sample")
    if index is not None and index.d != vector.size:
        raise ValueError("Dimensi fitur query berbeda dari atlas; rebuild atlas diperlukan")
    if index is not None:
        distances_raw, order_raw = index.search(vector.reshape(1, -1).astype(np.float32), min(neighbours, len(samples)))
        order = order_raw[0]
        distances = np.sqrt(np.maximum(distances_raw[0], 0.0))
    else:
        matrix = np.asarray([sample.vector for sample in samples], dtype=np.float32)
        all_distances = np.linalg.norm(matrix - vector, axis=1)
        order = np.argsort(all_distances)[: min(neighbours, len(samples))]
        distances = all_distances[order]
    weights = 1.0 / np.maximum(distances, 0.015) ** 2
    weights /= weights.sum()
    latitude = float(sum(samples[item].latitude * weight for item, weight in zip(order, weights)))
    longitude = float(sum(samples[item].longitude * weight for item, weight in zip(order, weights)))
    spread = float(sum(weight * haversine_km((latitude, longitude), (samples[item].latitude, samples[item].longitude)) for item, weight in zip(order, weights)))
    return latitude, longitude, spread, [(samples[item], float(distance)) for item, distance in zip(order, distances)]


def confidence_score(matches: list[tuple[Sample, float]], spread_km: float) -> float:
    """Heuristic quality signal, deliberately not a probability."""
    if not matches:
        return 0.0
    nearest = matches[0][1]
    separation = matches[1][1] - nearest if len(matches) > 1 else 0.0
    visual_signal = max(0.0, min(1.0, 1.0 - nearest))
    separation_signal = max(0.0, min(1.0, separation * 3.0))
    geographic_signal = max(0.0, min(1.0, 1.0 - spread_km / 500.0))
    return round(100.0 * (0.55 * visual_signal + 0.25 * separation_signal + 0.20 * geographic_signal), 1)


def evaluate(samples: list[Sample]) -> tuple[float, int]:
    if len(samples) < 2:
        return 0.0, 0
    errors = []
    for held_out, sample in enumerate(samples):
        pool = samples[:held_out] + samples[held_out + 1 :]
        prediction = predict(np.asarray(sample.vector), pool, neighbours=min(5, len(pool)))
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

st.markdown('<div class="mono eyebrow">ATLAS VISION / PRIVATE TRAINING</div>', unsafe_allow_html=True)
st.title("Private visual geolocation.")
st.markdown("<p class='lede'>Latih atlas dari foto berkoordinat nyata, lalu cari lokasi foto baru. Semua proses berjalan di server Streamlit dan atlas disimpan persisten di folder data, bukan di browser.</p>", unsafe_allow_html=True)
st.markdown('<div class="note"><b>Append-only training.</b> Data baru ditambahkan ke atlas dan metadata ditulis atomically. Tidak ada tombol hapus di UI. Commit snapshot <code>data/atlas.json</code> ke GitHub untuk backup versi.</div>', unsafe_allow_html=True)

train_tab, locate_tab, activity_tab, model_tab = st.tabs(["01 / TRAIN", "02 / LOCATE", "03 / ACTIVITY", "04 / MODEL"])

with train_tab:
    st.subheader("Build the visual atlas")
    st.write("Upload banyak foto sekaligus. Nama file wajib memuat pasangan latitude_longitude, misalnya `jalan__-6.2088_106.8456.jpg`.")
    uploads = st.file_uploader("Foto training berlabel koordinat", type=IMAGE_TYPES, accept_multiple_files=True, key="train_uploads")
    if uploads:
        valid, invalid = [], []
        for upload in uploads:
            if parse_coordinates(upload.name) is None:
                invalid.append(upload.name)
            else:
                valid.append(upload)
        st.write(f"{len(valid)} foto valid / {len(invalid)} ditolak")
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
            log_event("train", uploaded=len(valid), added=added, total=len(st.session_state.samples))
            st.success(f"{added} foto baru disisipkan ke FAISS. Total atlas: {len(st.session_state.samples)}.")
    if st.session_state.samples:
        error, count = evaluate(st.session_state.samples)
        cols = st.columns(3)
        cols[0].metric("Training images", len(st.session_state.samples))
        cols[1].metric("Validation mean error", f"{error:.1f} km" if count else "Need 2+")
        cols[2].metric("Feature dimensions", len(st.session_state.samples[0].vector))
        st.dataframe([{ "file": item.name, "latitude": item.latitude, "longitude": item.longitude } for item in st.session_state.samples], width="stretch", hide_index=True)
    else:
        st.info("Belum ada data. Mulai dengan upload beberapa foto yang punya koordinat nyata di nama file.")

with locate_tab:
    st.subheader("Locate an unseen image")
    neighbours = st.slider("Number of visual neighbours", min_value=1, max_value=15, value=5, help="Lebih banyak tetangga membuat hasil lebih stabil, tetapi dapat mengurangi ketajaman lokasi.")
    query = st.file_uploader("Foto yang ingin diprediksi", type=IMAGE_TYPES, accept_multiple_files=False, key="query_upload")
    if query and st.session_state.samples:
        image = image_bytes(query)
        latitude, longitude, spread, matches = predict(visual_vector(image), st.session_state.samples, st.session_state.atlas_index, neighbours=neighbours)
        confidence = confidence_score(matches, spread)
        log_event("locate", file=query.name, latitude=latitude, longitude=longitude, spread_km=spread)
        left, right = st.columns([1, 1.2])
        with left:
            st.image(image, caption=query.name, width="stretch")
        with right:
            st.metric("Estimated latitude", f"{latitude:.6f}")
            st.metric("Estimated longitude", f"{longitude:.6f}")
            st.metric("Neighbour spread", f"{spread:.1f} km")
            st.metric("Match quality", f"{confidence:.1f}/100")
            st.caption("Match quality adalah sinyal kualitas berbasis jarak visual dan konsistensi tetangga, bukan probabilitas kebenaran.")
        st.write("Nearest visual matches")
        st.dataframe([{ "file": sample.name, "visual distance": round(distance, 4), "latitude": sample.latitude, "longitude": sample.longitude } for sample, distance in matches], width="stretch", hide_index=True)
        st.map({"latitude": [latitude], "longitude": [longitude]}, latitude="latitude", longitude="longitude", zoom=10)
    elif not st.session_state.samples:
        st.info("Train atlas terlebih dahulu.")

with activity_tab:
    st.subheader("Training and locate history")
    events = read_events()
    if events:
        st.dataframe(list(reversed(events)), width="stretch", hide_index=True)
    else:
        st.info("Belum ada aktivitas tersimpan.")

with model_tab:
    st.subheader("Save or restore your model")
    st.write("Model berisi feature vector dan koordinat training. Semua tetap lokal dan dapat diaudit.")
    if st.session_state.samples:
        st.download_button("Download atlas model", export_model(st.session_state.samples), "atlas-vision.json", "application/json")
    restored = st.file_uploader("Restore atlas model", type=["json"], key="restore_model")
    if restored and st.button("Restore model"):
        try:
            st.session_state.samples = import_model(restored)
            st.session_state.atlas_index = _new_index(len(st.session_state.samples[0].vector)) if st.session_state.samples else None
            if st.session_state.samples:
                st.session_state.atlas_index.add(np.asarray([sample.vector for sample in st.session_state.samples], dtype=np.float32))
                persist_atlas(st.session_state.atlas_index, st.session_state.samples)
            log_event("restore", total=len(st.session_state.samples))
            st.success(f"{len(st.session_state.samples)} sample berhasil dipulihkan.")
        except (ValueError, KeyError, json.JSONDecodeError) as error:
            st.error(str(error))
    st.info("Atlas bersifat append-only dari UI. Penghapusan manual tidak disediakan agar data training tidak hilang.")

st.markdown("<p class='mono' style='margin-top:3rem;color:#65736d'>LOCAL FEATURES / EXPLAINABLE MATCHING / NO PRETRAINED WEIGHTS</p>", unsafe_allow_html=True)