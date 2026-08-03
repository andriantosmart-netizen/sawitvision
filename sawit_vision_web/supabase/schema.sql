-- ============================================================================
-- SawitVision — Skema Supabase (Postgres)
-- ============================================================================
-- Jalankan seluruh file ini di: Supabase Dashboard → SQL Editor → New query
-- (atau via `supabase db push` jika pakai Supabase CLI).
--
-- Arsitektur multi-tenant sederhana:
--   companies       = satu baris per kebun/perusahaan (unit yang berlangganan)
--   devices         = satu baris per HP (anonymous auth user = 1 device)
--   admin_profiles  = akun login web dashboard (email/password), terhubung ke 1 company
--   scan_results    = hasil scan janjang/brondol dari HP (sync dari SQLite lokal)
--   training_photos = foto tambahan untuk dataset training yang diupload lewat web
--
-- Prinsip keamanan: SEMUA akses lewat Row Level Security (RLS). Anon key
-- (public) yang dipakai di app mobile & web TIDAK bisa baca/tulis data
-- company lain karena dibatasi policy di bawah.
-- ============================================================================

create extension if not exists pgcrypto; -- untuk gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 1. companies
-- ----------------------------------------------------------------------------
create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  kode text not null unique, -- kode pendek yang diinput di app mobile, mis. "KEBUNA01"
  created_at timestamptz not null default now()
);

alter table companies enable row level security;

-- Siapa saja (termasuk anon) boleh CEK apakah suatu kode kebun valid saat
-- registrasi device — tapi hanya kolom kode & id yang relevan, tidak ada data
-- sensitif di tabel ini sehingga select terbatas ini aman.
create policy "companies_select_by_kode" on companies
  for select using (true);

-- ----------------------------------------------------------------------------
-- 2. devices  (id = auth.uid() dari Supabase Anonymous Auth di HP)
-- ----------------------------------------------------------------------------
create table if not exists devices (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  device_name text,
  worker_name text,
  last_sync_at timestamptz,
  created_at timestamptz not null default now()
);

alter table devices enable row level security;

create policy "devices_insert_self" on devices
  for insert with check (id = auth.uid());

create policy "devices_update_self" on devices
  for update using (id = auth.uid());

create policy "devices_select_self_or_admin" on devices
  for select using (
    id = auth.uid()
    or exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = devices.company_id
    )
  );

-- ----------------------------------------------------------------------------
-- 3. admin_profiles  (akun web dashboard, id = auth.users.id via email/password)
-- ----------------------------------------------------------------------------
create table if not exists admin_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  nama text,
  created_at timestamptz not null default now()
);

alter table admin_profiles enable row level security;

create policy "admin_profiles_select_self" on admin_profiles
  for select using (id = auth.uid());

-- Catatan: pembuatan baris admin_profiles baru sengaja TIDAK dibuka lewat
-- policy insert publik. Tambahkan admin baru manual lewat SQL Editor
-- (lihat docs/SETUP_SUPABASE_WEB.md) supaya tidak sembarang orang bisa
-- mendaftar sebagai admin company manapun.

-- ----------------------------------------------------------------------------
-- 4. scan_results  (mirror dari tabel scan_results SQLite di mobile)
-- ----------------------------------------------------------------------------
create table if not exists scan_results (
  id uuid primary key, -- sama dengan id yang digenerate mobile (uuid v4)
  company_id uuid not null references companies(id) on delete cascade,
  device_id uuid not null references devices(id) on delete cascade,
  mode text not null check (mode in ('janjang', 'brondol')),
  jumlah_janjang int not null default 0,
  estimasi_brondol int not null default 0,
  ukuran_janjang text not null default 'sedang',
  persen_brondol numeric not null default 0,
  fraksi text not null default 'f00',
  blok text not null default '',
  catatan text not null default '',
  latitude double precision,
  longitude double precision,
  photo_path text, -- path di storage bucket 'scan-photos'
  captured_at timestamptz not null,
  synced_at timestamptz not null default now()
);

alter table scan_results enable row level security;

create policy "scan_results_insert_own_device" on scan_results
  for insert with check (
    device_id = auth.uid()
    and company_id = (select company_id from devices where id = auth.uid())
  );

create policy "scan_results_select_own_or_admin" on scan_results
  for select using (
    device_id = auth.uid()
    or exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = scan_results.company_id
    )
  );

-- Upsert dari HP (mis. edit catatan lalu sync ulang) dibatasi ke device pemilik data.
create policy "scan_results_update_own_device" on scan_results
  for update using (device_id = auth.uid());

create index if not exists idx_scan_results_company_date
  on scan_results (company_id, captured_at desc);

-- ----------------------------------------------------------------------------
-- 5. training_photos  (foto tambahan untuk dataset, diupload dari web dashboard)
-- ----------------------------------------------------------------------------
create table if not exists training_photos (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  label text not null check (label in ('janjang', 'brondol', 'janjang_kosong')),
  photo_path text not null, -- path di storage bucket 'training-photos'
  source text not null default 'web_upload' check (source in ('web_upload', 'mobile')),
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table training_photos enable row level security;

create policy "training_photos_admin_all" on training_photos
  for all using (
    exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = training_photos.company_id
    )
  ) with check (
    exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = training_photos.company_id
    )
  );

-- ----------------------------------------------------------------------------
-- 6. Fungsi join_company — dipanggil mobile app sekali saat setup awal
--    (isi "Kode Kebun" di layar Settings), memakai kredensial anonim device.
-- ----------------------------------------------------------------------------
create or replace function join_company(p_kode text, p_device_name text, p_worker_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select id into v_company_id from companies where kode = p_kode;

  if v_company_id is null then
    raise exception 'Kode kebun/perusahaan tidak ditemukan: %', p_kode;
  end if;

  insert into devices (id, company_id, device_name, worker_name, last_sync_at)
  values (auth.uid(), v_company_id, p_device_name, p_worker_name, now())
  on conflict (id) do update
    set company_id = excluded.company_id,
        device_name = excluded.device_name,
        worker_name = excluded.worker_name;

  return v_company_id;
end;
$$;

-- Izinkan role anon & authenticated (termasuk anonymous auth users) memanggil fungsi ini.
grant execute on function join_company(text, text, text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 7. Storage buckets & policies
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('scan-photos', 'scan-photos', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('training-photos', 'training-photos', false)
on conflict (id) do nothing;

-- Konvensi path: scan-photos/{company_id}/{scan_id}.jpg
-- Konvensi path: training-photos/{company_id}/{uuid}.jpg
-- (storage.foldername(name))[1] mengambil segmen folder pertama = company_id.

create policy "scan_photos_insert_own_device" on storage.objects
  for insert with check (
    bucket_id = 'scan-photos'
    and (storage.foldername(name))[1] = (
      select company_id::text from devices where id = auth.uid()
    )
  );

create policy "scan_photos_select_own_or_admin" on storage.objects
  for select using (
    bucket_id = 'scan-photos'
    and (
      (storage.foldername(name))[1] = (select company_id::text from devices where id = auth.uid())
      or (storage.foldername(name))[1] in (
        select company_id::text from admin_profiles where id = auth.uid()
      )
    )
  );

create policy "training_photos_admin_all_objects" on storage.objects
  for all using (
    bucket_id = 'training-photos'
    and (storage.foldername(name))[1] in (
      select company_id::text from admin_profiles where id = auth.uid()
    )
  ) with check (
    bucket_id = 'training-photos'
    and (storage.foldername(name))[1] in (
      select company_id::text from admin_profiles where id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 8. Koreksi & Bounding Box (fitur "Koreksi Data" di web dashboard)
-- ----------------------------------------------------------------------------
-- Foto yang diimpor dari sumber lain (mis. sistem e-Panen internal) sering
-- kali jumlah JJG/BRD di levelnya adalah agregat per batch (No.e-BHP), BUKAN
-- per foto — jadi belum tentu cocok persis dengan apa yang terlihat di satu
-- foto tertentu. Kolom & tabel di bawah menyimpan hasil KOREKSI MANUSIA per
-- foto (lewat halaman koreksi.html): kotak pembatas (bounding box) di tiap
-- objek + jumlah final yang sudah dikonfirmasi seorang admin/kerani.

alter table training_photos add column if not exists verified boolean not null default false;
alter table training_photos add column if not exists verified_jjg_count int;
alter table training_photos add column if not exists verified_brd_count int;
alter table training_photos add column if not exists verified_by uuid references auth.users(id);
alter table training_photos add column if not exists verified_at timestamptz;
-- Catatan asal data, mis. "No.e-BHP: BHP.SRIE1.202607161721441 — JJG/BRD
-- agregat batch, belum tentu sesuai foto ini persis" — supaya jejak asal
-- data tetap tercatat walau sudah dikoreksi.
alter table training_photos add column if not exists source_note text;

create table if not exists photo_annotations (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references training_photos(id) on delete cascade,
  company_id uuid not null references companies(id) on delete cascade,
  object_class text not null check (object_class in ('janjang', 'brondol', 'janjang_kosong')),
  -- Koordinat kotak, ternormalisasi 0-1 relatif ke ukuran asli foto (x,y = sudut
  -- kiri-atas), format yang sama dengan konvensi YOLO supaya gampang dikonversi
  -- langsung oleh training_pipeline/convert_web_annotations.py.
  x numeric not null,
  y numeric not null,
  width numeric not null,
  height numeric not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table photo_annotations enable row level security;

create policy "photo_annotations_admin_all" on photo_annotations
  for all using (
    exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = photo_annotations.company_id
    )
  ) with check (
    exists (
      select 1 from admin_profiles ap
      where ap.id = auth.uid() and ap.company_id = photo_annotations.company_id
    )
  );

create index if not exists idx_photo_annotations_photo on photo_annotations (photo_id);

-- ----------------------------------------------------------------------------
-- 9. Kategori "Janjang Kosong" (tandan tanpa buah, setara Fraksi 5 — ditolak)
-- ----------------------------------------------------------------------------
-- Kotak (BB) berwarna merah di koreksi.html. Migrasi ini AMAN dijalankan ulang
-- (idempotent) baik di project baru (constraint di atas sudah termasuk kelas
-- ini) maupun project lama yang dibuat sebelum kelas ini ada.
alter table training_photos add column if not exists verified_jjgkosong_count int;

alter table training_photos drop constraint if exists training_photos_label_check;
alter table training_photos add constraint training_photos_label_check
  check (label in ('janjang', 'brondol', 'janjang_kosong'));

alter table photo_annotations drop constraint if exists photo_annotations_object_class_check;
alter table photo_annotations add constraint photo_annotations_object_class_check
  check (object_class in ('janjang', 'brondol', 'janjang_kosong'));

-- ============================================================================
-- Selesai. Langkah berikutnya ada di docs/SETUP_SUPABASE_WEB.md:
--   1. Insert 1 baris ke tabel `companies` untuk kebun Anda.
--   2. Buat akun admin (auth user + baris admin_profiles).
--   3. Salin Project URL & anon key ke config mobile app & web dashboard.
-- ============================================================================
