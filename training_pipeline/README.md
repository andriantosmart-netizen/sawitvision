# Training Pipeline — Model Custom Deteksi Janjang, Brondol & Janjang Kosong

Update 2026-08-02: setelah pendekatan heuristik CV (warna + bentuk + tekstur) di
`koreksi.html` mentok di beberapa latar foto yang membingungkan (kayu/batu pucat
mirip warna buah), kita putuskan coba model terlatih sungguhan — **YOLO26n**
(Ultralytics, rilis Januari 2026, varian "nano" — paling ringan/cepat, cocok
untuk HP). Folder ini berisi seluruh pipeline: dari data mentah sampai model
`.tflite` siap pakai di aplikasi Flutter.

Aplikasi SawitVision **tidak wajib** menunggu tahap ini — mode "CV Klasik" di
`koreksi.html` sudah bisa dipakai sekarang. Pipeline ini untuk meningkatkan
akurasi setelah model terlatih siap.

## Status data saat ini (2026-08-02)

Dari `sawitvision_annotations.json` yang sudah ada:

| Kelas | Foto terverifikasi | Kotak (instance) |
|---|---|---|
| Janjang | 67 (1 batch, 16 Juli, lokasi/cahaya seragam) | 460 |
| Brondol | sama, 67 foto | 84 |
| Janjang Kosong | sama, 67 foto | 2 |

Secara ANGKA, 460 kotak Janjang sebenarnya sudah masuk kisaran wajar untuk
fine-tune model nano (rule of thumb praktisi: ~150-300 foto/kelas minimum,
500+ untuk hasil lebih tahan banting — lihat referensi di bawah). Masalahnya
BUKAN jumlah, tapi KERAGAMAN: 67 foto itu semuanya dari 1 sesi pemotretan
(lokasi & cahaya mirip semua) — model yang cuma belajar dari ini berisiko
tidak kenal latar lain (rumput beda, TPH beton, kayu/batu, cahaya mendung dsb),
persis masalah yang bikin heuristik CV kita gagal di foto kayu kemarin.

Brondol untuk sekarang **dilewati dulu** (fokus ke Janjang atas keputusan
pengguna 2026-08-02) — sumber foto Brondol akan dicari terpisah nanti karena
`Sintang_T20_220726.xlsx` ternyata isinya 100% foto Janjang (kolom
`foto_jjg_a`/`foto_jjg_b`, tidak ada kolom Brondol sama sekali).

## Rencana penambahan data Janjang (2026-08-02)

`Sintang_T20_220726.xlsx` punya 58.027 link foto Janjang, tersebar di 9 unit
kebun (SKSE, SDSE, SJNE, SSPE, SJNA, SKSA, SANE, SSPA, SANA) & 22 tanggal
panen (1-22 Juli 2026), 656 blok berbeda — jauh lebih beragam dari 67 foto
yang sudah ada. Target ronde ini: **300 foto BARU**, disebar rata ke semua
unit & tanggal (bukan cuma 300 foto pertama di file, yang akan menumpuk di
1-2 tanggal saja) — supaya total jadi ~367 foto Janjang terverifikasi dari
lokasi/cahaya yang jauh lebih beragam.

### 1. Unduh sample baru (di komputer Anda, VPN kantor aktif)

```bash
pip install openpyxl requests
python download_jjg_photos.py --xlsx Sintang_T20_220726.xlsx \
    --outdir foto_jjg_batch2 --sample 300 --strategy stratified \
    --exclude-existing foto_training_sawit
```

`--strategy stratified` menyebar foto rata ke semua unit & tanggal (lihat
`stratified_sample()` di `download_jjg_photos.py`). `--exclude-existing`
memastikan tidak mengunduh ulang foto yang sudah ada di folder
`foto_training_sawit` (194 foto yang sudah pernah diproses). Cek
`foto_jjg_batch2/manifest.csv` setelah selesai — sama seperti sebelumnya.

### 2. Buat draft kotak otomatis (BUKAN gambar dari nol)

Pindahkan foto baru ke folder yang sama dengan `koreksi.html`
(`foto_training_sawit` atau folder kerja Anda), buka `koreksi.html`
(sekarang cukup 1 klik "🔗 Hubungkan Folder Kerja"), lalu di panel
"Deteksi Otomatis Berdasarkan Karakteristik Object": pilih target Janjang,
klik **"Terapkan ke SEMUA Foto"** — ini menjalankan detektor stem-scar +
gerbang bentuk/warna terbaru (lihat catatan di `koreksi.html`) ke seluruh
batch sekaligus, menghasilkan draft kotak per foto.

**Draft ini BUKAN keputusan final** — status "terverifikasi" otomatis
direset supaya wajib diperiksa. Alur reviewnya jauh lebih cepat daripada
gambar dari nol: buka tiap foto, benarkan kotak yang salah/kurang/lebih,
lalu centang "Sudah saya periksa & koreksi". Kotak dengan %keyakinan
rendah (label ungu di atas kotak, atau foto dengan peringatan "⚠️ kandidat
jauh lebih banyak dari biasanya") butuh perhatian ekstra — kemungkinan
besar itu yang salah.

> Alternatif command-line: `auto_annotate_cv.py` di folder ini melakukan hal
> serupa lewat Python (hasil `pre_annotations.json` bisa diimpor ke
> `koreksi.html`), TAPI masih pakai logika deteksi warna LAMA (sebelum
> gerbang bentuk/tekstur 2026-08-02) — kalau mau pakai jalur ini, script-nya
> perlu disamakan dulu dengan `detectJanjangByStemScar()` versi terbaru di
> `koreksi.html`. Untuk sekarang, jalur browser ("Terapkan ke SEMUA Foto")
> lebih disarankan karena sudah otomatis konsisten dengan detektor terbaru.

### 3. Export & konversi ke format YOLO

```bash
# Di koreksi.html: klik "3. Simpan / Export (JSON)" -> sawitvision_annotations.json

python convert_web_annotations.py \
    --json sawitvision_annotations.json \
    --images foto_training_sawit \
    --out raw
python prepare_dataset.py --raw raw --out dataset --classes janjang brondol janjang_kosong
```

## 4. Training butuh GPU — jalankan di komputer/laptop Anda

Sandbox cloud yang dipakai Claude di sesi ini **cuma CPU (2 core, tanpa
GPU)** — training YOLO (walau versi nano) di situ tidak realistis (bisa
berjam-jam bahkan untuk beberapa ratus foto). Sudah dikonfirmasi bersama:
training dijalankan di **komputer/laptop Anda**. Kalau punya GPU NVIDIA,
`train_yolov8.py` otomatis mendeteksi & memakainya; kalau tidak, tetap bisa
jalan di CPU tapi jauh lebih lambat — pertimbangkan Google Colab (GPU
gratis, ada batas pemakaian) sebagai alternatif kalau training di CPU
terasa terlalu lama.

```bash
pip install -r requirements.txt
# Kalau ada GPU NVIDIA, install PyTorch versi CUDA DULU sebelum baris di
# atas -- lihat https://pytorch.org/get-started/locally/

python train_yolov8.py --data dataset/data.yaml
```

Script ini otomatis mengecek & melaporkan apakah GPU terdeteksi sebelum
mulai training. Default model: `yolo26n.pt` (YOLO26 nano, pretrained COCO,
transfer learning). Kalau `ultralytics` yang terpasang belum mendukung
YOLO26 (`pip install -U ultralytics` untuk versi terbaru), fallback ke
`--model yolov8n.pt`.

Opsi umum:

```bash
python train_yolov8.py --data dataset/data.yaml --epochs 150 --imgsz 640
python train_yolov8.py --data dataset/data.yaml --device cpu   # paksa CPU
```

## 5. Export ke TFLite

```bash
python export_to_tflite.py --weights runs/detect/sawit_train/weights/best.pt --half
```

Menghasilkan `sawit_detector.tflite` — salin ke `assets/models/` pada
project Flutter, samakan urutan kelas di `assets/labels/labels.txt` dengan
`names` di `dataset/data.yaml`, aktifkan mode "Model Custom (TFLite)" di
Settings, lalu uji ke beberapa foto nyata dulu sebelum dipakai penuh.

`lib/services/tflite_detection_service.dart` mengasumsikan output model
bergaya YOLO (`[1, N, 5+num_classes]`) — YOLO26 pakai format output serupa
tapi NMS-free (end-to-end); cek dulu bentuk output aktualnya kalau parsing
hasil deteksi di aplikasi tidak sesuai ekspektasi, sesuaikan
`_parseYoloOutput` kalau perlu.

## Kumpulkan foto Brondol (terpisah, menyusul)

`Sintang_T20_220726.xlsx` tidak punya foto Brondol sama sekali. Untuk
menyeimbangkan dataset (target sama, ~300-500 foto), butuh sumber lain —
mis. export sistem "setoran brondolan"/timbang kalau ada, atau instruksi ke
tim lapangan untuk memfoto tumpukan brondol secara terpisah (seperti 44 foto
Brondol yang sudah ada di `foto_training_sawit`). Sampai itu tersedia, model
ini fokus Janjang dulu — kelas Brondol tetap disertakan di `dataset/data.yaml`
(dari 84 kotak yang sudah ada) supaya struktur kelasnya konsisten, tapi
jangan berharap akurasi Brondol setara Janjang di ronde pertama ini.

## Referensi jumlah data minimum

- Roboflow: hasil layak mulai ~50-150 foto/kelas, disarankan ≥200/kelas
  untuk hasil baik, lebih banyak lagi kalau latar/cahaya/sudut bervariasi.
- Ultralytics (panduan tips training YOLOv5, masih relevan): ≥1500
  foto/kelas & ≥10.000 instance/kelas untuk model tingkat produksi — tapi
  transfer learning dari bobot pretrained COCO bekerja jauh dengan data
  lebih sedikit dari itu.
- Untuk fine-tune nano 2 kelas di latar lapangan nyata (kondisi kita): mulai
  layak di kisaran 150-300 foto/kelas, 500+ untuk lebih tahan banting
  lintas kondisi cahaya/latar.
