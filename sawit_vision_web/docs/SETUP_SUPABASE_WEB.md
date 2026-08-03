# Setup Supabase + Deploy Web Dashboard

Panduan ini mengasumsikan Anda memilih opsi paling praktis: **Supabase**
(Postgres + Storage + Auth, tier gratis cukup untuk skala 1 kebun/beberapa
puluh device) dan **Vercel/Netlify** untuk hosting web dashboard statis
(gratis, drag-and-drop, tanpa perlu server sendiri).

Tidak butuh command line/koding tambahan — semua langkah lewat web UI.

---

## 1. Buat project Supabase

1. Daftar/masuk ke https://supabase.com, klik **New project**.
2. Catat **Project URL** dan **anon public key** — nanti dipakai di
   `assets/config.js` (web) dan `lib/config/supabase_config.dart` (mobile).
   Kedua nilai ini ada di **Project Settings → API**.

## 2. Jalankan skema database

1. Buka **SQL Editor** di dashboard Supabase → **New query**.
2. Copy-paste seluruh isi file `supabase/schema.sql` dari paket ini, klik
   **Run**.
3. Pastikan tidak ada error. Ini membuat semua tabel, RLS policy, fungsi
   `join_company`, dan storage bucket (`scan-photos`, `training-photos`).

## 3. Aktifkan Anonymous Sign-in (dipakai app mobile)

1. **Authentication → Providers → Anonymous Sign-Ins** → aktifkan (Enable).
   Tanpa ini, app mobile tidak bisa mendaftarkan device.

## 4. Buat data kebun/perusahaan Anda

Di **SQL Editor**, jalankan (ganti nilai sesuai kebutuhan):

```sql
insert into companies (nama, kode)
values ('Kebun Sawit A', 'KEBUNA01');
```

`kode` inilah yang nanti diinput karyawan di layar Pengaturan aplikasi
mobile untuk mendaftarkan HP mereka.

## 5. Buat akun admin pertama (untuk login web dashboard)

1. **Authentication → Users → Add user** → isi email & password admin
   Anda → **Create user**. Centang "Auto Confirm User" supaya tidak perlu
   verifikasi email.
2. Salin **User UID** yang baru dibuat.
3. Di **SQL Editor**, hubungkan admin ini ke company (ganti UID & kode):

   ```sql
   insert into admin_profiles (id, company_id, nama)
   values (
     'PASTE-USER-UID-DI-SINI',
     (select id from companies where kode = 'KEBUNA01'),
     'Nama Admin'
   );
   ```

Untuk menambah admin lain nanti (mis. staf kantor lain), ulangi langkah 5
dengan email berbeda.

## 6. Isi konfigurasi di kode

- **Web**: buka `assets/config.js`, ganti `SUPABASE_URL` dan
  `SUPABASE_ANON_KEY` dengan nilai dari langkah 1.
- **Mobile**: buka `lib/config/supabase_config.dart` (di paket
  `sawit_vision`), ganti nilai yang sama.

## 7. Deploy web dashboard

Web dashboard ini adalah HTML/JS statis murni (tanpa build step), jadi
bisa langsung di-deploy ke layanan static hosting gratis:

**Opsi A — Netlify (drag & drop, paling simpel):**
1. Buka https://app.netlify.com/drop
2. Drag seluruh folder `sawit_vision_web` (kecuali folder `supabase/` dan
   `docs/` boleh ikut, tidak masalah) ke halaman tersebut.
3. Netlify langsung memberi URL publik, mis. `https://nama-acak.netlify.app`.

**Opsi B — Vercel:**
1. Buat project baru di https://vercel.com/new, pilih "Deploy without Git"
   / upload folder.
2. Upload folder `sawit_vision_web`.

**Opsi C — buka langsung dari komputer (paling cepat untuk uji coba):**
Buka file `index.html` langsung di browser (double-click). Supabase Auth
& query tetap berfungsi karena semua request ke Supabase pakai HTTPS
absolut, bukan relative path. Untuk pemakaian tim sehari-hari, tetap lebih
baik deploy ke hosting (Opsi A/B) supaya ada URL yang bisa dibuka siapa saja.

## 8. Login & coba

1. Buka URL web dashboard, login pakai akun admin dari langkah 5.
2. Di HP, buka aplikasi SawitVision → Pengaturan → Sinkronisasi Cloud →
   isi Kode Kebun (`KEBUNA01`) → Daftarkan Device.
3. Lakukan 1 scan janjang/brondol di HP, tunggu sampai tersinkron
   (otomatis saat online, atau tekan "Sync Sekarang").
4. Refresh halaman `dashboard.html` di web — data & foto harusnya sudah
   muncul.

---

## Troubleshooting singkat

- **"Akun ini belum terdaftar sebagai admin"** saat login web → berarti
  langkah 5 (insert ke `admin_profiles`) belum dilakukan/salah UID.
- **Device gagal daftar dari HP** ("Kode kebun tidak ditemukan") → cek
  ejaan `kode` di tabel `companies`, dan pastikan Anonymous Sign-in
  (langkah 3) sudah aktif.
- **Foto tidak muncul di galeri web** → cek Storage → Policies di
  Supabase Dashboard, pastikan bucket `scan-photos`/`training-photos`
  beserta policy-nya berhasil dibuat dari `schema.sql` (lihat tab
  **Storage** untuk verifikasi bucket ada).
- **Biaya** → tier gratis Supabase mencakup 500MB database + 1GB storage
  + 50.000 monthly active users, cukup besar untuk tahap awal. Pantau
  penggunaan di **Project Settings → Usage** jika jumlah device/foto
  bertambah banyak.
