// ============================================================================
// Kredensial project Supabase Anda.
//
// Isi kedua nilai di bawah SETELAH membuat project Supabase & menjalankan
// supabase/schema.sql (lihat docs/SETUP_SUPABASE_WEB.md).
//
// SUPABASE_ANON_KEY aman ditaruh di kode sisi client (bukan rahasia) karena
// semua akses tetap dibatasi Row Level Security di database. JANGAN PERNAH
// menaruh "service_role key" di file ini.
// ============================================================================
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';

window.SAWIT_CONFIG = { SUPABASE_URL, SUPABASE_ANON_KEY };

window.isSupabaseConfigured = function () {
  return (
    SUPABASE_URL !== 'https://YOUR-PROJECT-REF.supabase.co' &&
    SUPABASE_ANON_KEY !== 'YOUR-ANON-PUBLIC-KEY' &&
    SUPABASE_URL.startsWith('https://')
  );
};

// Dibuat sekali, dipakai di semua halaman (index.html, dashboard.html, dst.)
// Membutuhkan <script src=".../@supabase/supabase-js@2"></script> dimuat
// SEBELUM file ini di setiap halaman HTML.
if (window.isSupabaseConfigured()) {
  window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
}
