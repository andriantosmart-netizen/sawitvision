import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/scan_result.dart';
import 'database_service.dart';
import 'settings_service.dart';
import 'supabase_service.dart';

class SyncResult {
  final int total;
  final int berhasil;
  final int gagal;
  final String? error;

  const SyncResult({
    required this.total,
    required this.berhasil,
    required this.gagal,
    this.error,
  });

  static const disabled = SyncResult(total: 0, berhasil: 0, gagal: 0);
}

/// Mengunggah scan yang belum tersinkron ke Supabase (web dashboard), baik
/// otomatis begitu koneksi internet tersedia maupun lewat tombol manual.
///
/// Fitur ini 100% opsional dan aman untuk diabaikan:
/// - Jika `lib/config/supabase_config.dart` belum diisi kredensial asli,
///   semua method di sini langsung return tanpa melakukan apapun.
/// - Jika device belum didaftarkan ke sebuah company/kebun (lihat
///   SettingsScreen), sync juga tidak berjalan.
/// - Kegagalan jaringan tidak pernah menghapus/merusak data lokal — data
///   tetap tersimpan di SQLite dan akan dicoba lagi di kesempatan berikutnya.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  bool get _readyToSync => SupabaseConfig.isConfigured;

  /// Panggil sekali di main.dart (setelah SupabaseService.init() jika
  /// dikonfigurasi) untuk mulai memantau koneksi internet dan auto-sync.
  void startAutoSyncListener() {
    if (!_readyToSync) return;
    _connectivitySub?.cancel();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) return;

      final settings = SettingsService();
      final autoEnabled = await settings.getAutoSyncEnabled();
      final registered = await settings.isDeviceRegistered();
      if (autoEnabled && registered) {
        await syncPending();
      }
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
  }

  Future<bool> hasInternet() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Upload semua scan yang belum tersinkron. Aman dipanggil berkali-kali
  /// (mis. dari tombol "Sync Sekarang") — tidak akan berjalan dobel karena
  /// dijaga flag [_syncing].
  Future<SyncResult> syncPending() async {
    if (!_readyToSync) return SyncResult.disabled;
    if (_syncing) return SyncResult.disabled;

    final settings = SettingsService();
    final companyId = await settings.getCompanyId();
    if (companyId == null) return SyncResult.disabled;

    if (!await hasInternet()) {
      return const SyncResult(total: 0, berhasil: 0, gagal: 0, error: 'offline');
    }

    _syncing = true;
    try {
      final deviceId = await SupabaseService.instance.ensureSignedIn();
      final pending = await DatabaseService.instance.getUnsyncedScans();

      int berhasil = 0;
      int gagal = 0;

      for (final scan in pending) {
        final ok = await _syncOne(scan, companyId: companyId, deviceId: deviceId);
        if (ok) {
          berhasil++;
        } else {
          gagal++;
        }
      }

      await settings.setLastSyncAt(DateTime.now());
      await _touchDeviceLastSync();

      return SyncResult(total: pending.length, berhasil: berhasil, gagal: gagal);
    } catch (e) {
      return SyncResult(total: 0, berhasil: 0, gagal: 0, error: e.toString());
    } finally {
      _syncing = false;
    }
  }

  Future<bool> _syncOne(
    ScanResult scan, {
    required String companyId,
    required String deviceId,
  }) async {
    try {
      final client = SupabaseService.instance.client;
      final photoFile = File(scan.imagePath);
      final storagePath = '$companyId/${scan.id}.jpg';

      if (await photoFile.exists()) {
        await client.storage.from('scan-photos').upload(
              storagePath,
              photoFile,
              fileOptions: const FileOptions(upsert: true),
            );
      }

      final payload = scan.toSupabasePayload(companyId: companyId, deviceId: deviceId);
      await client.from('scan_results').upsert(payload);

      await DatabaseService.instance.markSynced(scan.id);
      return true;
    } catch (e) {
      // Dibiarkan gagal untuk item ini saja — akan dicoba lagi di sync
      // berikutnya. Tidak melempar exception supaya item lain tetap diproses.
      return false;
    }
  }

  Future<void> _touchDeviceLastSync() async {
    try {
      final client = SupabaseService.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client
          .from('devices')
          .update({'last_sync_at': DateTime.now().toIso8601String()}).eq('id', uid);
    } catch (_) {
      // Tidak kritis — abaikan jika gagal update timestamp.
    }
  }
}
