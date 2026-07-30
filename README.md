# SawitVision

Aplikasi mobile Android **offline** untuk membantu proses panen kelapa
sawit:

- **Hitung Janjang** — hitung jumlah tandan buah segar (TBS) dari foto
  tumpukan hasil panen di TPH.
- **Taksasi Brondol** — estimasi jumlah brondolan (buah lepas) dan
  konversinya ke standar **Fraksi Kematangan** industri sawit, untuk
  membantu penentuan kualitas/grade panen.

Semua proses inti (kamera → deteksi → hitung → simpan) berjalan langsung
di HP, tanpa internet. Cocok dipakai di kebun dengan sinyal lemah/tidak
ada. Ada juga fitur **sinkronisasi cloud opsional** ke paket
`sawit_vision_web` — begitu HP terhubung wifi/internet, foto & hasil scan
bisa terkirim ke web dashboard untuk dipantau kantor sekaligus terkumpul
jadi dataset training model AI. Lihat bagian "Sinkronisasi ke Web
Dashboard" di bawah.

Baca `docs/ARSITEKTUR.md` untuk penjelasan lengkap desain teknis, logic
grading, dan alasan di balik keputusan desain (termasuk kenapa ada 2 mode
deteksi).

## Status project ini

Ini adalah **kode sumber lengkap** siap-build, dikembangkan tanpa dataset
foto sawit yang berlabel (karena belum tersedia). Supaya tetap fungsional
hari ini, mode deteksi default memakai **Computer Vision klasik** (color +
blob detection) — bukan cuma UI mockup, tapi benar-benar mendeteksi &
menghitung objek dari foto. Saat Anda sudah mengumpulkan dataset foto
lapangan, tinggal jalankan `training_pipeline/` untuk melatih model AI
custom yang jauh lebih akurat, tanpa perlu mengubah kode UI.

## Cara Mendapatkan APK & Install ke HP

Ada 2 jalur. Pilih **Opsi A** kalau Anda/tim tidak punya laptop developer
dengan Flutter terinstall — semua proses build jalan di cloud, gratis.
Pilih **Opsi B** kalau Anda (atau developer Anda) sudah/ingin punya
Flutter SDK di komputer sendiri (lebih cepat untuk iterasi berulang).

### Opsi A — Build via Codemagic (tanpa install apapun di komputer)

1. Buat akun gratis di https://github.com (kalau belum punya), buat
   **repository baru** (public atau private, bebas), lalu upload **seluruh
   isi folder `sawit_vision`** dari paket ini ke repo tersebut (termasuk
   file `codemagic.yaml` — jangan dihapus, itu resep buildnya).
2. Daftar/login ke https://codemagic.io pakai akun GitHub yang sama
   (tier gratis cukup untuk beberapa build/bulan).
3. **Add application** → pilih repo `sawit_vision` tadi. Codemagic otomatis
   mendeteksi `codemagic.yaml` dan menawarkan workflow **"SawitVision —
   Build APK Android"**.
4. Klik **Start new build**. Tunggu ±10 menit — Codemagic akan otomatis
   men-generate folder `android/` yang belum ada, menambahkan izin kamera,
   lalu build APK-nya (tanpa Anda perlu install Flutter/Android Studio
   sama sekali).
5. Setelah build hijau (sukses), buka halaman build tersebut → bagian
   **Artifacts** → unduh file `app-release.apk`.
6. Kirim file APK itu ke HP Android (via Google Drive, email, atau kabel
   USB), buka file-nya di HP File Manager, izinkan **"Install dari sumber
   tidak dikenal"** jika muncul prompt, lalu **Install**.
7. Buka aplikasi **SawitVision** dari home screen HP — selesai.

> APK dari jalur ini ditandatangani pakai debug key bawaan Flutter — aman
> dan cukup untuk dipakai internal (sideload ke HP karyawan). Kalau nanti
> ingin publikasi resmi di Google Play, perlu setup signing key sendiri
> (di luar cakupan panduan ini, developer Anda bisa bantu saat itu).

### Opsi B — Build manual dengan Flutter SDK lokal

1. **Install Flutter SDK**: ikuti
   https://docs.flutter.dev/get-started/install lalu jalankan
   `flutter doctor` untuk memastikan Android toolchain siap.

2. **Generate scaffolding platform** di dalam folder project ini:

   ```bash
   cd sawit_vision
   flutter create --platforms=android --org com.sawitvision .
   ```

   Perintah ini membuat folder `android/` lengkap (gradle, manifest,
   ikon default, dst.) tanpa menimpa `lib/`, `pubspec.yaml`, atau
   `assets/` yang sudah ada.

3. **Tambahkan permission kamera** di
   `android/app/src/main/AndroidManifest.xml` (di dalam tag
   `<manifest>`, sebelum `<application>`):

   ```xml
   <uses-permission android:name="android.permission.CAMERA" />
   <uses-feature android:name="android.hardware.camera" android:required="true" />
   ```

4. **Install dependencies & jalankan**:

   ```bash
   flutter pub get
   flutter run          # jalankan langsung di HP yang terhubung kabel USB
   flutter build apk    # atau build APK release untuk dibagikan
   ```

   APK hasil build ada di `build/app/outputs/flutter-apk/app-release.apk`
   — kirim & install ke HP dengan cara yang sama seperti Opsi A langkah 6-7.

### Melihat tampilan tanpa build dulu

File `preview/sawitvision_preview.html` di paket ini adalah mockup visual
statis (HTML, bukan aplikasi Flutter sungguhan) untuk melihat gambaran
tampilan tiap layar sebelum Anda build APK-nya.

## Struktur folder

```
lib/                  # seluruh kode Dart aplikasi
  config/              # supabase_config.dart — kredensial sync (opsional)
  models/              # entitas data (ScanResult, Fraksi, dll.)
  services/            # deteksi, database, grading, export, settings, sync
  screens/             # layar UI
  widgets/             # komponen UI kecil yang dipakai ulang
  utils/               # konstanta, tema warna
assets/
  models/              # tempat taruh model .tflite custom (opsional)
  labels/              # label kelas untuk model custom
training_pipeline/     # script Python untuk training model custom
preview/
  sawitvision_preview.html  # mockup visual tampilan (lihat sebelum build)
docs/
  ARSITEKTUR.md         # dokumen desain teknis lengkap
codemagic.yaml          # resep build APK otomatis via Codemagic (Opsi A)
```

## Sinkronisasi ke Web Dashboard (opsional)

Aplikasi tetap 100% berfungsi tanpa fitur ini. Untuk mengaktifkannya:

1. Ikuti setup Supabase & deploy web dashboard di paket `sawit_vision_web`
   (`docs/SETUP_SUPABASE_WEB.md` di paket tersebut).
2. Isi `lib/config/supabase_config.dart` dengan URL & anon key project
   Supabase Anda.
3. `flutter pub get` ulang (ada 2 dependency baru: `supabase_flutter`,
   `connectivity_plus`).
4. Di aplikasi, buka **Pengaturan → Sinkronisasi Cloud**, isi Kode
   Kebun/Perusahaan, lalu **Daftarkan Device**.

Setelah itu, setiap kali hasil scan disimpan, aplikasi akan mencoba
mengirimnya ke web dashboard di latar belakang (jika sedang online) — dan
otomatis mencoba lagi begitu koneksi internet tersedia. Tombol "Sync
Sekarang" di halaman Beranda/Pengaturan bisa dipakai kapan saja sebagai
cadangan. Data yang belum terkirim tetap aman tersimpan di SQLite lokal.

## Kalibrasi & akurasi

Mode CV Klasik memakai threshold warna yang bisa perlu disetel ulang
tergantung kondisi kebun Anda (jenis tanah, pencahayaan, varietas sawit).
Titik yang bisa disesuaikan:

- `lib/services/cv_detection_service.dart` — fungsi `_isRipeOrange` dan
  `_isJanjangHusk`, serta rentang ukuran blob (`minBlobAreaRatio*`,
  `maxBlobAreaRatio*`).
- Layar Settings di aplikasi — faktor koreksi brondol tertumpuk, ukuran
  janjang default, dan ambang batas persentase tiap Fraksi.

## Privasi & data

Tidak ada data (foto, hasil hitung, lokasi) yang dikirim ke server
manapun. Semua tersimpan lokal di database SQLite pada HP. Fitur "Ekspor"
di halaman Riwayat hanya membuat file CSV lokal yang bisa Anda bagikan
manual (WhatsApp/Email/Drive) sesuai kebutuhan pelaporan ke kantor/PKS.
