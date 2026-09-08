# Atlas Vision

Atlas Vision adalah aplikasi geolocation vision lokal yang dibuat tanpa GeoCLIP, PyTorch, model cloud, atau bobot pretrained. Modelnya membangun descriptor multi-view dari warna, komposisi ruang, tekstur tepi, statistik gambar, dan grid pixel RGB beresolusi rendah, lalu melakukan weighted nearest-neighbor melalui FAISS terhadap foto berlabel.

## Jalankan

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/streamlit run app.py
```

## Penyimpanan aman

Aplikasi hanya menggunakan Streamlit. Training tersimpan di server pada `data/atlas.json`, index pencarian di `data/atlas.index`, dan aktivitas di `data/events.jsonl`. UI tidak menyediakan aksi delete atau clear. Commit `data/atlas.json` ke GitHub setelah batch training untuk menyimpan snapshot versi.

## Test

```bash
.venv/bin/python -m unittest discover -s tests -v
```

## Format dataset

Upload banyak foto di tab **TRAIN**. Setiap nama file harus memiliki pasangan latitude dan longitude yang nyata:

```text
jakarta__-6.2088_106.8456.jpg
bandung__-6.9175_107.6191.jpg
```

Foto tanpa pasangan koordinat valid ditolak. Setelah training, gunakan tab **LOCATE** untuk mencari foto yang mirip dan melihat koordinat estimasi serta spread kandidat dalam kilometer.

Setiap training baru di-append ke `data/atlas.index`. Metadata recovery disimpan di `data/atlas.json`, dan aktivitas lokal disimpan di `data/events.jsonl`. Foto mentah tidak pernah ditulis ke disk; yang disimpan hanya vector fitur dan koordinat. UI utama berfokus pada locate; mode train tersedia untuk menambahkan foto berkoordinat dan otomatis dikosongkan setelah training.

Descriptor menggunakan beberapa view dari foto: crop aman, mirror, rotasi kecil, brightness, dan contrast. Semua view digabung menjadi satu vector dengan grid pixel RGB `16x16` serta grid luminance mikro `24x24` dan gradien lokal. FAISS selalu mengembalikan satu hasil terdekat untuk mempercepat query dan mempersempit lokasi. Ini membantu, tetapi tidak menyelesaikan perbedaan sudut 3D besar atau mengenali lokasi yang belum terwakili dataset.

## Catatan akurasi

Model lokal ini bukan pengganti model geolocation pretrained dengan dataset global berskala jutaan. Repository ini tidak menyertakan dataset 5 juta gambar atau pipeline training sebesar itu; akurasi tetap bergantung pada kualitas dan cakupan foto yang dilatih. Hasil visual confidence adalah sinyal heuristik, bukan jaminan atau probabilitas kebenaran. Kota dan negara hasil lacak memakai reverse geocoding OpenStreetMap.