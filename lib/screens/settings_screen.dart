import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _kodeController = TextEditingController();
  final _namaController = TextEditingController();
  bool _loading = true;

  DetectionEngine _engine = DetectionEngine.cvKlasik;
  double _occlusionFactor = 1.4;
  double _tfliteConfidence = 0.35;

  bool _deviceRegistered = false;
  bool _autoSync = true;
  DateTime? _lastSyncAt;
  bool _syncing = false;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kodeController.dispose();
    _namaController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final engine = await _settings.getEngine();
    final factor = await _settings.getOcclusionFactor();
    final tfliteConfidence = await _settings.getTfliteConfidenceThreshold();
    final registered = await _settings.isDeviceRegistered();
    final autoSync = await _settings.getAutoSyncEnabled();
    final lastSync = await _settings.getLastSyncAt();
    final kode = await _settings.getCompanyKode();
    final worker = await _settings.getWorkerName();

    setState(() {
      _engine = engine;
      _occlusionFactor = factor;
      _tfliteConfidence = tfliteConfidence;
      _deviceRegistered = registered;
      _autoSync = autoSync;
      _lastSyncAt = lastSync;
      _kodeController.text = kode ?? '';
      _namaController.text = worker ?? '';
      _loading = false;
    });
  }

  Future<void> _daftarkanDevice() async {
    if (_kodeController.text.trim().isEmpty) {
      setState(() => _syncMessage = 'Isi kode kebun/perusahaan terlebih dahulu.');
      return;
    }
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    try {
      final companyId = await SupabaseService.instance.joinCompany(
        kode: _kodeController.text.trim(),
        deviceName: 'HP Lapangan',
        workerName: _namaController.text.trim(),
      );
      await _settings.saveDeviceRegistration(
        companyId: companyId,
        kode: _kodeController.text.trim(),
        workerName: _namaController.text.trim(),
      );
      setState(() {
        _deviceRegistered = true;
        _syncMessage = 'Device berhasil didaftarkan ke kebun.';
      });
    } catch (e) {
      setState(() => _syncMessage = 'Gagal mendaftar: $e');
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<void> _syncSekarang() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    final result = await SyncService.instance.syncPending();
    setState(() {
      _syncing = false;
      if (result.error == 'offline') {
        _syncMessage = 'Tidak ada koneksi internet. Coba lagi nanti.';
      } else if (result.error != null) {
        _syncMessage = 'Sync gagal: ${result.error}';
      } else {
        _syncMessage =
            'Sync selesai: ${result.berhasil} berhasil, ${result.gagal} gagal dari ${result.total} data.';
      }
    });
    final lastSync = await _settings.getLastSyncAt();
    setState(() => _lastSyncAt = lastSync);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text('Mesin Deteksi', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                RadioListTile<DetectionEngine>(
                  title: const Text('CV Klasik (default)'),
                  subtitle: const Text('Langsung jalan tanpa training, cocok dipakai sekarang.'),
                  value: DetectionEngine.cvKlasik,
                  groupValue: _engine,
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _engine = v);
                    await _settings.setEngine(v);
                  },
                ),
                RadioListTile<DetectionEngine>(
                  title: const Text('Model Custom (TFLite)'),
                  subtitle: const Text(
                      'Model YOLO26n hasil training sendiri (assets/models/sawit_detector.tflite). '
                      'Jika file belum ada, otomatis kembali ke CV Klasik.'),
                  value: DetectionEngine.tflite,
                  groupValue: _engine,
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _engine = v);
                    await _settings.setEngine(v);
                  },
                ),
                if (_engine == DetectionEngine.tflite) ...[
                  const SizedBox(height: 4),
                  const Text('Ambang Confidence Model Custom',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Text(
                    'Deteksi dengan confidence di bawah nilai ini diabaikan. Naikkan '
                    'kalau terlalu banyak kotak salah/palsu muncul; turunkan kalau '
                    'terlalu banyak objek yang tidak tertangkap.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Slider(
                    value: _tfliteConfidence,
                    min: 0.1,
                    max: 0.9,
                    divisions: 16,
                    label: '${(_tfliteConfidence * 100).toStringAsFixed(0)}%',
                    onChanged: (v) => setState(() => _tfliteConfidence = v),
                    onChangeEnd: (v) =>
                        _settings.setTfliteConfidenceThreshold(v),
                  ),
                  Text(
                      'Ambang saat ini: ${(_tfliteConfidence * 100).toStringAsFixed(0)}%'),
                ],
                const Divider(height: 32),
                const Text('Faktor Koreksi Brondol Tertumpuk',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Text(
                  'Brondol yang tertutup/tumpuk di bagian bawah tidak selalu terlihat kamera. '
                  'Faktor ini mengalikan jumlah yang terlihat untuk estimasi total.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Slider(
                  value: _occlusionFactor,
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  label: _occlusionFactor.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _occlusionFactor = v),
                  onChangeEnd: (v) => _settings.setOcclusionFactor(v),
                ),
                Text('Faktor saat ini: ${_occlusionFactor.toStringAsFixed(2)}x'),
                const Divider(height: 32),
                const Text('Sinkronisasi Cloud (Opsional)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (!SupabaseConfig.isConfigured)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Belum aktif. Isi lib/config/supabase_config.dart dengan kredensial '
                      'project Supabase Anda untuk mengaktifkan sinkronisasi foto & data ke '
                      'web dashboard (lihat paket sawit_vision_web).',
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else ...[
                  const Text(
                    'Kirim foto & hasil scan ke web dashboard untuk dipantau kantor dan '
                    'dipakai sebagai data training model AI. Aplikasi tetap berjalan penuh '
                    'tanpa fitur ini.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _kodeController,
                    enabled: !_deviceRegistered,
                    decoration: const InputDecoration(
                      labelText: 'Kode Kebun/Perusahaan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _namaController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Karyawan (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!_deviceRegistered)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _syncing ? null : _daftarkanDevice,
                        child: _syncing
                            ? const SizedBox(
                                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Daftarkan Device'),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Device terdaftar ke kebun ini.')),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sync otomatis saat online'),
                      value: _autoSync,
                      onChanged: (v) async {
                        setState(() => _autoSync = v);
                        await _settings.setAutoSyncEnabled(v);
                      },
                    ),
                    Text(
                      _lastSyncAt == null
                          ? 'Belum pernah sync.'
                          : 'Terakhir sync: ${DateFormat('dd MMM yyyy, HH:mm').format(_lastSyncAt!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: _syncing
                            ? const SizedBox(
                                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: const Text('Sync Sekarang'),
                        onPressed: _syncing ? null : _syncSekarang,
                      ),
                    ),
                  ],
                  if (_syncMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(_syncMessage!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
                const Divider(height: 32),
                const Text('Tentang Aplikasi', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'SawitVision v0.1.0 — deteksi & penghitungan tetap berjalan offline di '
                  'perangkat ini. Sinkronisasi cloud (jika diaktifkan) hanya mengirim foto '
                  'dan hasil scan yang Anda simpan, ke project Supabase milik Anda sendiri.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
    );
  }
}
