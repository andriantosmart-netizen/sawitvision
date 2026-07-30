/// Kredensial project Supabase Anda.
///
/// Isi kedua nilai ini SETELAH membuat project Supabase & menjalankan
/// `supabase/schema.sql` dari paket `sawit_vision_web` — panduan lengkap ada
/// di docs/SETUP_SUPABASE_WEB.md (paket web).
///
/// `anonKey` aman ditaruh di kode aplikasi (bukan rahasia) karena semua
/// akses tetap dibatasi Row Level Security di database, BUKAN oleh key ini.
/// Jangan pernah taruh `service_role key` di sini.
class SupabaseConfig {
  static const String url = 'https://YOUR-PROJECT-REF.supabase.co';
  static const String anonKey = 'YOUR-ANON-PUBLIC-KEY';

  /// Sinkronisasi otomatis dimatikan sampai kredensial di atas diisi, supaya
  /// aplikasi tidak crash mencoba konek ke URL placeholder.
  static bool get isConfigured =>
      url != 'https://YOUR-PROJECT-REF.supabase.co' &&
      anonKey != 'YOUR-ANON-PUBLIC-KEY' &&
      url.startsWith('https://');
}
