# SawitVision — Arsitektur Teknis

Aplikasi mobile Android **offline-first** untuk membantu mandor/karyawan panen kelapa sawit:
1. Menghitung jumlah **janjang** (Tandan Buah Segar / TBS) dalam satu foto tumpukan hasil panen di TPH (Tempat Pengumpulan Hasil).
2. Melakukan **taksasi (estimasi) brondolan** yang lepas dari tandan, lalu memetakannya ke standar **Fraksi Kematangan** industri sawit untuk menentukan kualitas/grade panen.

Semua proses (foto → deteksi → hitung → simpan) berjalan **100% di perangkat**, tanpa koneksi internet. Tidak ada data yang dikirim ke server manapun.

---

## 1. Kenapa harus offline?

Kebun sawit umumnya berada di area dengan sinyal seluler lemah/tidak ada. Maka:
- Model AI/CV berjalan on-device (tidak hit API cloud).
- Penyimpanan pakai database lokal (SQLite via `sqflite`).
- Foto disimpan di local storage HP.
- Sinkronisasi/ekspor data (CSV) bersifat opsional, dilakukan manual saat ada sinyal/wifi kantor.

## 2. Kondisi data saat ini & strategi model AI

Belum ada dataset foto janjang/brondol yang berlabel. Supaya aplikasi **tetap bisa langsung dipakai hari ini** (bukan cuma mockup UI), dibuat 2 mode deteksi yang bisa dipilih di Settings:

| Mode | Cara kerja | Butuh training? | Akurasi |
|---|---|---|---|
| **CV Klasik (default)** | Threshold warna (HSV) untuk buah sawit matang (oranye-kemerahan) + hitam, lalu deteksi blob/kontur, hitung objek, estimasi ukuran | Tidak — jalan langsung | Cukup untuk estimasi lapangan, sensitif terhadap pencahayaan |
| **TFLite (model custom)** | Model deteksi objek terlatih (mis. YOLOv8 nano → export TFLite) untuk kelas `janjang` dan `brondol` | Ya — butuh dataset berlabel | Jauh lebih akurat setelah dilatih |

Aplikasi dibangun agar mode TFLite tinggal "plug-in": begitu ada model `.tflite` hasil training (lihat `training_pipeline/`), taruh di `assets/models/`, aktifkan di Settings, tanpa mengubah kode UI/database.

**Rekomendasi jangka pendek:** mulai kumpulkan 200-500 foto janjang & brondol dari lapangan (berbagai kondisi cahaya/kematangan) sambil pakai mode CV Klasik. Setelah data cukup, latih model custom pakai `training_pipeline/` agar akurasi naik signifikan.

## 3. Standar Fraksi Kematangan (dasar logic grading)

Industri sawit Indonesia memakai standar fraksi berdasarkan persentase buah luar yang sudah membrondol (lepas) dari janjang:

| Fraksi | Kondisi | % Brondol (perkiraan) | Kategori |
|---|---|---|---|
| 00 | Sangat mentah, buah hitam semua | 0% | Tolak |
| 0 | Mentah | 1 – 12.5% | Kurang matang |
| 1 | Kurang matang | 12.5 – 25% | Kurang matang |
| 2 | Matang I | 25 – 50% | **Ideal panen** |
| 3 | Matang II | 50 – 75% | **Ideal panen** |
| 4 | Lewat matang I | 75 – 100% | Lewat matang |
| 5 | Lewat matang II, janjang kosong | >100% / buah dalam ikut lepas | Tolak |

> Catatan: persentase di atas adalah acuan umum. Setiap PKS/kebun biasanya punya SOP sendiri — nilai ambang batas ini dibuat **bisa dikonfigurasi** di Settings agar sesuai kebijakan perusahaan Anda.

**Logic taksasi:**
1. User pilih kategori ukuran janjang (Kecil/Sedang/Besar) → aplikasi pakai referensi jumlah brondol total per kategori (dapat dikalibrasi di Settings, default berbasis referensi agronomi ± 1000-2000 brondol/janjang).
2. Untuk taksasi tumpukan brondol yang sudah terlepas: user meletakkan **kartu referensi ukuran** (misal kartu 8.5×5.5 cm) di sebelah tumpukan sebagai kalibrasi skala, foto diambil dari atas.
3. Aplikasi mendeteksi area tumpukan, menghitung kepadatan brondol per cm² pada sub-area sampel, lalu ekstrapolasi ke luas total tumpukan → estimasi jumlah brondol.
4. `% brondol = brondol_terdeteksi / referensi_total_brondol_janjang × 100` → dipetakan ke tabel Fraksi di atas.

## 4. Struktur Aplikasi (Flutter)

```
lib/
  main.dart                     # entry point
  app.dart                      # MaterialApp, tema, routing
  models/
    scan_result.dart            # entitas hasil scan (janjang/brondol)
    fraksi.dart                 # enum & tabel fraksi kematangan
  services/
    database_service.dart       # sqflite — simpan/ambil riwayat scan
    detection_service.dart      # interface abstrak deteksi
    cv_detection_service.dart   # implementasi CV klasik (default)
    tflite_detection_service.dart # implementasi model custom (pluggable)
    grading_service.dart        # hitung fraksi & grade dari hasil deteksi
    settings_service.dart       # simpan preferensi/kalibrasi (shared_preferences)
    export_service.dart         # ekspor riwayat ke CSV
  screens/
    splash_screen.dart
    home_screen.dart            # dashboard ringkasan hari ini
    scan_screen.dart            # kamera + pilih mode (Janjang/Brondol)
    result_screen.dart          # overlay deteksi + form simpan (blok, catatan)
    history_screen.dart         # daftar riwayat scan, filter tanggal/blok
    detail_screen.dart          # detail 1 scan
    stats_screen.dart           # grafik ringkas (fl_chart)
    settings_screen.dart        # mode deteksi, kalibrasi, ekspor data
  widgets/
    bounding_box_painter.dart   # gambar kotak/lingkaran deteksi di atas foto
    stat_card.dart
    grade_badge.dart
  utils/
    constants.dart
```

Android/iOS scaffolding (folder `android/`, `ios/`) **tidak** disertakan mentah di paket ini karena berisi banyak berkas biner (gradle wrapper, dsb.) yang idealnya digenerate langsung oleh Flutter CLI di komputer Anda — lihat `README.md` bagian "Cara Build" untuk langkah lengkapnya (2 perintah saja).

## 5. Alur data (data flow)

```
Kamera / Galeri
      │
      ▼
DetectionService (CV / TFLite)
      │  → List<DetectedObject> {label, bbox, confidence}
      ▼
GradingService
      │  → jumlah janjang, estimasi brondol, % fraksi, grade
      ▼
ResultScreen (user bisa koreksi manual jumlah jika deteksi meleset)
      │
      ▼
DatabaseService (SQLite lokal)
      │
      ▼
HistoryScreen / StatsScreen / ExportService (CSV)
      │
      ▼ (opsional, jika sync diaktifkan)
SyncService → Supabase Storage (foto) + Supabase Postgres (data)
      │
      ▼
Web Dashboard (sawit_vision_web) — monitoring + galeri dataset training
```

## 7. Sinkronisasi Cloud & Web Dashboard (opsional)

Fitur tambahan agar foto & hasil scan dari banyak HP bisa terkumpul di
satu tempat untuk (a) dipantau kantor dan (b) dipakai sebagai dataset
training model AI custom. Detail lengkap ada di paket terpisah
`sawit_vision_web` (web dashboard statis + skema Supabase +
`docs/SETUP_SUPABASE_WEB.md`).

Poin desain penting:
- **Tetap offline-first**: fitur ini murni tambahan. Tanpa konfigurasi
  Supabase, seluruh kode sync (`lib/services/sync_service.dart`,
  `supabase_service.dart`) tidak pernah dipanggil (`SupabaseConfig.isConfigured`
  jadi gerbang utamanya).
- **Sync oportunistik**: `connectivity_plus` memantau perubahan koneksi;
  begitu online, antrian scan yang belum terkirim (`synced = 0` di SQLite)
  otomatis diunggah. Tombol manual "Sync Sekarang" tersedia sebagai cadangan.
- **Multi-tenant lewat Row Level Security**: satu "company" = satu
  kebun/perusahaan. Device (HP) memakai Supabase Anonymous Auth, didaftarkan
  ke company lewat "Kode Kebun" yang diinput sekali di Settings. Admin web
  login lewat email/password terpisah. RLS policy di `schema.sql` memastikan
  satu company tidak bisa melihat data company lain.
- **Dataset training gabungan**: setiap foto scan yang tersinkron otomatis
  ikut jadi sampel dataset (label = mode scan). Tim kantor bisa menambah
  foto lain langsung dari web dashboard (`photos.html`) untuk memperkaya
  variasi data sebelum training lewat `training_pipeline/`.

## 6. Roadmap lanjutan

1. **Kumpulkan dataset** (foto lapangan) — target awal 300-500 foto per kelas.
2. **Label** pakai tools gratis: Roboflow / CVAT / LabelImg.
3. **Training** model deteksi ringan (YOLOv8n / EfficientDet-Lite) — script scaffold ada di `training_pipeline/`.
4. **Export ke TFLite**, taruh di `assets/models/sawit_detector.tflite`, aktifkan mode TFLite di Settings.
5. Opsional: tambah GPS tagging per blok kebun, sinkronisasi ke sistem pelaporan kantor saat ada wifi.
