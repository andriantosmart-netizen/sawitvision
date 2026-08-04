import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_result.dart';
import '../services/detection_service.dart';
import '../services/cv_detection_service.dart';
import '../services/tflite_detection_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import '../widgets/bounding_box_editor.dart';

/// Layar hasil: menjalankan deteksi otomatis (kecuali sudah dibawa dari
/// [LiveCameraScreen] lewat [initialBoxes]), lalu menampilkan foto dengan
/// [BoundingBoxEditor] penuh (gambar/geser/resize/hapus/reklasifikasi
/// kotak) -- padanan langsung koreksi.html di Web. Semua angka (Jumlah
/// Janjang, Janjang Kosong, Tumpukan Brondol) dihitung OTOMATIS dari jumlah
/// kotak per kelas, jadi selalu sinkron dengan apa yang benar-benar
/// ditandai di foto.
class ResultScreen extends StatefulWidget {
  final String imagePath;
  final ScanMode mode;

  /// Kotak yang sudah ditandai (deteksi live + tap manual) dari
  /// [LiveCameraScreen], kalau foto diambil lewat kamera live. Null/kosong
  /// kalau foto berasal dari galeri -- dalam kasus itu layar ini yang
  /// menjalankan deteksi dari awal (lihat [_runDetection]).
  final List<DetectedObject>? initialBoxes;

  const ResultScreen({
    super.key,
    required this.imagePath,
    required this.mode,
    this.initialBoxes,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _settings = SettingsService();
  final _blokController = TextEditingController();
  final _catatanController = TextEditingController();
  final _customKgController = TextEditingController();

  bool _loading = true;
  String? _engineUsedFallbackNote;
  double _avgConfidence = 0;

  List<DetectedObject> _boxes = [];
  late String _activeClass;

  static const _kgPresets = [3.0, 5.0, 7.0];
  double _kgPerTumpukan = 5.0;
  bool _useCustomKg = false;

  List<BoxClassOption> get _classOptions => [
        const BoxClassOption(
          label: 'janjang',
          displayName: 'Janjang',
          shortName: 'Jjg',
          color: AppColors.primary,
        ),
        const BoxClassOption(
          label: 'brondol',
          displayName: 'Tumpukan Brondol',
          shortName: 'Brd',
          color: AppColors.accent,
        ),
        const BoxClassOption(
          label: 'janjang_kosong',
          displayName: 'Janjang Kosong',
          shortName: 'Jangkos',
          color: Color(0xFFC62828),
        ),
      ];

  int get _janjangCount => _boxes.where((b) => b.label == 'janjang').length;
  int get _janjangKosongCount =>
      _boxes.where((b) => b.label == 'janjang_kosong').length;
  int get _brondolTumpukanCount =>
      _boxes.where((b) => b.label == 'brondol').length;
  double get _finalKg => _brondolTumpukanCount * _kgPerTumpukan;

  @override
  void initState() {
    super.initState();
    _activeClass = widget.mode == ScanMode.brondol ? 'brondol' : 'janjang';
    _init();
  }

  @override
  void dispose() {
    _blokController.dispose();
    _catatanController.dispose();
    _customKgController.dispose();
    super.dispose();
  }

  String _formatKg(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _init() async {
    _kgPerTumpukan = await _settings.getBrdKgPerTumpukan();
    _useCustomKg = !_kgPresets.contains(_kgPerTumpukan);
    _customKgController.text = _formatKg(_kgPerTumpukan);

    final initial = widget.initialBoxes;
    if (initial != null && initial.isNotEmpty) {
      // Sudah ditag lewat LiveCameraScreen (deteksi live + tap manual) --
      // pakai langsung, tidak perlu jalankan deteksi ulang di foto final
      // (asumsi framing sama dengan preview live terakhir sebelum jepret).
      setState(() {
        _boxes = List<DetectedObject>.from(initial);
        _loading = false;
      });
      return;
    }
    await _runDetection();
  }

  Future<void> _runDetection() async {
    setState(() => _loading = true);

    final occlusion = await _settings.getOcclusionFactor();
    final engine = await _settings.getEngine();
    final tfliteConfidence = await _settings.getTfliteConfidenceThreshold();

    final bytes = await File(widget.imagePath).readAsBytes();

    DetectionService service = CvDetectionService(occlusionFactor: occlusion);
    String? fallbackNote;

    if (engine == DetectionEngine.tflite) {
      final tflite = TfliteDetectionService(
        occlusionFactor: occlusion,
        confidenceThreshold: tfliteConfidence,
      );
      try {
        final result = await tflite.detect(imageBytes: bytes, mode: widget.mode);
        setState(() {
          _boxes = List<DetectedObject>.from(result.objects);
          _avgConfidence = result.avgConfidence;
          _loading = false;
        });
        return;
      } catch (e) {
        fallbackNote =
            'Model custom belum tersedia — memakai mode CV Klasik sebagai gantinya.';
      }
    }

    final result = await service.detect(imageBytes: bytes, mode: widget.mode);
    setState(() {
      _boxes = List<DetectedObject>.from(result.objects);
      _avgConfidence = result.avgConfidence;
      _engineUsedFallbackNote = fallbackNote;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final isBrondol = widget.mode == ScanMode.brondol;

    final scan = ScanResult(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      imagePath: widget.imagePath,
      mode: widget.mode,
      jumlahJanjang: _janjangCount,
      estimasiBrondol: _brondolTumpukanCount,
      janjangKosong: _janjangKosongCount,
      brdKgPerTumpukan: isBrondol ? _kgPerTumpukan : 0,
      brdFinalKg: isBrondol ? _finalKg : 0,
      blok: _blokController.text.trim(),
      catatan: _catatanController.text.trim(),
    );

    await DatabaseService.instance.insertScan(scan);

    if (isBrondol) {
      // Ingat kalibrasi kg/tumpukan terakhir supaya scan berikutnya tidak
      // perlu pilih ulang (kalau memang konsisten).
      unawaited(_settings.setBrdKgPerTumpukan(_kgPerTumpukan));
    }

    // Coba sync di latar belakang jika fitur cloud sync aktif — sengaja
    // tidak di-await supaya user tidak menunggu upload sebelum lanjut
    // memindai. Jika offline/gagal, data tetap aman di SQLite lokal dan
    // akan dicoba lagi otomatis nanti.
    unawaited(SyncService.instance.syncPending());

    if (!mounted) return;

    // Ambil referensi Navigator & ScaffoldMessenger SEBELUM pop, karena
    // context milik layar ini tidak lagi valid setelah route-nya dilepas.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    navigator.popUntil((r) => r.settings.name == '/home' || r.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Hasil scan tersimpan.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBrondol = widget.mode == ScanMode.brondol;

    return Scaffold(
      appBar: AppBar(title: Text('Hasil — ${widget.mode.label}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (_engineUsedFallbackNote != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_engineUsedFallbackNote!,
                        style: const TextStyle(fontSize: 12)),
                  ),
                BoundingBoxEditor(
                  image: FileImage(File(widget.imagePath)),
                  boxes: _boxes,
                  onChanged: (next) => setState(() => _boxes = next),
                  classOptions: _classOptions,
                  activeClass: _activeClass,
                  onActiveClassChanged: (c) => setState(() => _activeClass = c),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Terdeteksi otomatis awal: ${_boxes.length} objek '
                  '(confidence rata-rata ${(_avgConfidence * 100).toStringAsFixed(0)}%). '
                  'Tambah/hapus/geser kotak langsung di foto kalau ada yang kurang tepat.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: AppSpacing.md),
                if (isBrondol) ...[
                  _buildBrondolSection(),
                ] else ...[
                  _buildJanjangSection(),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _blokController,
                  decoration: const InputDecoration(
                    labelText: 'Blok / Lokasi Kebun',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _catatanController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('Simpan Hasil'),
                    onPressed: _save,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildJanjangSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jumlah Janjang: $_janjangCount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Janjang Kosong: $_janjangKosongCount',
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 2),
          const Text(
            'Angka di atas otomatis mengikuti jumlah kotak di foto -- tambah '
            'kotak kelas "Janjang"/"Janjang Kosong" untuk mengoreksi.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildBrondolSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tumpukan Brondol: $_brondolTumpukanCount',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (_janjangKosongCount > 0) ...[
            const SizedBox(height: 4),
            Text('Janjang Kosong: $_janjangKosongCount',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text('Kg per Tumpukan', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ..._kgPresets.map((p) {
                final selected = !_useCustomKg && _kgPerTumpukan == p;
                return ChoiceChip(
                  label: Text('${_formatKg(p)} kg'),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _useCustomKg = false;
                    _kgPerTumpukan = p;
                  }),
                );
              }),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _useCustomKg,
                onSelected: (_) => setState(() {
                  _useCustomKg = true;
                  _customKgController.text = _formatKg(_kgPerTumpukan);
                }),
              ),
            ],
          ),
          if (_useCustomKg) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _customKgController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Kg per tumpukan (custom)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                final parsed = double.tryParse(v.replaceAll(',', '.'));
                if (parsed != null && parsed > 0) {
                  setState(() => _kgPerTumpukan = parsed);
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Final', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${_finalKg.toStringAsFixed(1)} kg',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$_brondolTumpukanCount tumpukan × ${_formatKg(_kgPerTumpukan)} kg/tumpukan',
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}
