import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Wrapper tipis di atas Supabase client untuk urusan autentikasi &
/// pendaftaran device ke sebuah company/kebun. Semua fitur di file ini
/// bersifat OPSIONAL — jika [SupabaseConfig.isConfigured] false, method di
/// sini tidak pernah dipanggil (lihat pemakaian di [SyncService]).
class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  bool _initialized = false;

  /// Panggil sekali di main.dart sebelum runApp(), HANYA jika
  /// SupabaseConfig.isConfigured == true.
  Future<void> init() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _initialized = true;
  }

  SupabaseClient get client => Supabase.instance.client;

  /// Pastikan device ini punya sesi Supabase Anonymous Auth. Satu sesi
  /// anonim = satu identitas device yang persisten di HP tersebut.
  Future<String> ensureSignedIn() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;

    final res = await client.auth.signInAnonymously();
    final user = res.user;
    if (user == null) {
      throw Exception('Gagal membuat sesi anonim ke Supabase.');
    }
    return user.id;
  }

  /// Daftarkan/hubungkan device ini ke sebuah company lewat kode kebun.
  /// Mengembalikan company_id jika berhasil, atau melempar exception dengan
  /// pesan yang bisa langsung ditampilkan ke user (mis. kode tidak ditemukan).
  Future<String> joinCompany({
    required String kode,
    required String deviceName,
    required String workerName,
  }) async {
    await ensureSignedIn();
    final result = await client.rpc('join_company', params: {
      'p_kode': kode.trim(),
      'p_device_name': deviceName.trim(),
      'p_worker_name': workerName.trim(),
    });
    return result as String;
  }
}
