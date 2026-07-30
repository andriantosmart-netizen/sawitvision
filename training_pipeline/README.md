# Training Pipeline — Model Custom Deteksi Janjang & Brondol

Folder ini berisi panduan & script untuk melatih model deteksi objek
custom begitu Anda sudah punya kumpulan foto janjang/brondol dari
lapangan. Hasil akhirnya adalah file `.tflite` yang tinggal ditaruh di
`assets/models/sawit_detector.tflite` pada project Flutter, lalu aktifkan
mode "Model Custom (TFLite)" di layar Settings aplikasi.

Aplikasi SawitVision **tidak wajib** menunggu tahap ini — mode "CV Klasik"
sudah bisa dipakai sekarang tanpa training apapun. Pipeline ini untuk
meningkatkan akurasi setelah Anda mengumpulkan cukup data.

## 1. Kumpulkan data (paling penting)

- Target awal: 300–500 foto per kelas (`janjang`, `brondol`), makin
  banyak makin baik.
- Variasikan: kondisi cahaya (pagi/siang/mendung), sudut foto, tingkat
  kematangan, latar (tanah, TPH beton, rumput), jarak kamera.
- Simpan foto asli (jangan di-crop dulu) — resolusi 1280–1920px cukup.
- Beri nama file yang jelas per lokasi/tanggal agar mudah ditelusuri.

## 2. Beri label (anotasi)

Gunakan salah satu tools gratis berikut untuk menggambar bounding box
pada tiap objek di foto:

- [Roboflow](https://roboflow.com) (berbasis web, ada tier gratis,
  langsung bisa export ke format YOLO)
- [CVAT](https://www.cvat.ai) (open source, bisa self-host)
- [LabelImg](https://github.com/HumanSignal/labelImg) (ringan, offline)

Export hasil label dalam format **YOLO** (`.txt` per gambar, 1 baris per
objek: `class_id x_center y_center width height`, semua ternormalisasi
0–1).

Struktur folder yang diharapkan skrip di bawah:

```
dataset/
  images/
    train/*.jpg
    val/*.jpg
  labels/
    train/*.txt
    val/*.txt
  data.yaml
```

`prepare_dataset.py` membantu membagi otomatis data mentah menjadi
train/val dengan rasio 80/20.

## 3. Install dependency training (di komputer/laptop, BUKAN di HP)

```bash
pip install -r requirements.txt
```

## 4. Latih model

```bash
python train_yolov8.py --data dataset/data.yaml --epochs 100 --imgsz 320
```

Model kecil (`yolov8n`) dipilih sebagai default karena harus jalan cepat
di HP. Sesuaikan `--epochs`/`--imgsz` sesuai kebutuhan akurasi vs ukuran
model.

## 5. Export ke TFLite

```bash
python export_to_tflite.py --weights runs/detect/train/weights/best.pt
```

Script ini menghasilkan `best_float16.tflite` (atau sesuai opsi
kuantisasi). Rename jadi `sawit_detector.tflite`, taruh di
`assets/models/` pada project Flutter, lalu update `labels.txt` di
`assets/labels/` sesuai urutan kelas di `data.yaml`.

## 6. Sesuaikan kode aplikasi jika perlu

`lib/services/tflite_detection_service.dart` mengasumsikan output model
bergaya YOLOv8 (`[1, N, 5+num_classes]`). Jika Anda mengganti arsitektur
model (mis. SSD MobileNet, EfficientDet), sesuaikan method
`_parseYoloOutput` di file tersebut dengan format output model Anda.
