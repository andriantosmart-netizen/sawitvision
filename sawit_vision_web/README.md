# SawitVision — Web Dashboard

Pasangan web dari aplikasi mobile **SawitVision**. Dua fungsi utama:

1. **Dashboard monitoring** — pantau hasil panen (jumlah janjang, taksasi
   brondol, fraksi kematangan) dari semua HP karyawan lapangan, terpusat
   per kebun/perusahaan.
2. **Kumpul & koreksi dataset training** — semua foto yang tersinkron dari HP
   otomatis ikut jadi bagian dataset, tim kantor bisa menambah foto lain
   lewat halaman upload, dan halaman **Koreksi Data** (`koreksi.html`)
   dipakai untuk menggambar bounding box + mengoreksi jumlah janjang/brondol
   final per foto (penting untuk foto impor dari sumber lain yang datanya
   cuma agregat per batch, belum tentu cocok persis per foto) — hasilnya
   dipakai untuk melatih model AI custom lewat `training_pipeline/` (ada di
   paket aplikasi mobile `sawit_vision`).

## Kenapa tanpa build step (bukan React/Next.js)?

Dibuat sebagai HTML/JS statis murni (pakai Supabase JS & Chart.js lewat
CDN) supaya bisa langsung dibuka atau di-deploy tanpa `npm install`/proses
build apapun — cukup upload foldernya ke static hosting mana saja.

## Struktur

```
index.html          # Login admin
dashboard.html       # Monitoring hasil panen (chart, tabel, filter, export CSV)
photos.html          # Galeri dataset + upload foto tambahan
koreksi.html          # Koreksi jumlah + gambar bounding box per foto (bisa dipakai
                       # tanpa login/Supabase — semua proses lokal di browser)
devices.html         # Daftar HP yang terdaftar per kebun
assets/
  config.js           # Isi kredensial Supabase Anda di sini
  app-common.js        # Helper bersama (auth guard, format tanggal, CSV, dst.)
supabase/
  schema.sql            # Skema database + RLS + storage policy, jalankan sekali di Supabase
docs/
  SETUP_SUPABASE_WEB.md  # Panduan lengkap langkah demi langkah
```

## Mulai cepat

1. Ikuti **`docs/SETUP_SUPABASE_WEB.md`** dari awal sampai akhir (buat
   project Supabase, jalankan schema, buat admin, isi config, deploy).
2. Sambungkan aplikasi mobile ke company yang sama lewat "Kode
   Kebun/Perusahaan" di layar Pengaturan.

## Keamanan

Semua akses data dibatasi Row Level Security (RLS) di Postgres — satu
company hanya bisa melihat datanya sendiri, diverifikasi di level
database, bukan cuma di kode frontend. `anon key` yang dipakai di
`assets/config.js` aman ditaruh di kode client karena tidak bisa
melewati RLS. Detail policy ada di `supabase/schema.sql`.
