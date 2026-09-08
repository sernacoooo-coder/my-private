# Atlas Vision

Atlas Vision adalah aplikasi geolocation vision lokal yang dibuat tanpa GeoCLIP, PyTorch, model cloud, atau bobot pretrained. Modelnya membangun descriptor visual multi-view dari warna, komposisi ruang, tekstur tepi, dan statistik gambar, lalu melakukan weighted nearest-neighbor melalui FAISS terhadap foto berlabel.

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

Setiap training baru di-append ke `data/atlas.index`. Metadata recovery disimpan di `data/atlas.json`, dan riwayat training maupun locate disimpan di `data/events.jsonl`. File lama tidak dihapus ketika batch baru ditambahkan. `data/atlas.json` adalah snapshot yang cocok dilacak Git; index FAISS dapat dibangun ulang dari metadata.

Descriptor menggunakan beberapa view dari foto: crop aman, mirror, rotasi kecil, brightness, dan contrast. Semua view digabung menjadi satu vector sehingga lebih tahan terhadap foto kecil, perubahan exposure, dan perubahan kecil pada framing. Ini membantu, tetapi tidak menyelesaikan perbedaan sudut 3D besar atau mengenali lokasi yang belum terwakili dataset.

## Catatan akurasi

Model lokal ini bukan pengganti dataset geolocation berskala besar seperti sistem komersial dengan data global. Akurasi bergantung pada jumlah, kualitas, dan cakupan geografis foto training. Aplikasi menampilkan leave-one-out mean error dan match quality sebagai sinyal evaluasi, bukan jaminan atau probabilitas kebenaran.