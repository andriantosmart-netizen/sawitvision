import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_result.dart';
import '../models/fraksi.dart';
import '../services/detection_service.dart';
import '../services/cv_detection_service.dart';
import '../services/tflite_detection_service.dart';
import '../services/settings_service.dart';
import '../services/grading_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../utils/constants.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/grade_badge.dart';

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final ScanMode mode;

  const ResultScreen({super.key, required this.imagePath, required this.mode});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _settings = SettingsService();
  final _grading = const GradingService();
  final _blokController = TextEditingController();
  final _catatanController = TextEditingController();

  bool _loading = true;
  String? _engineUsedFallbackNote;
  DetectionOutput _detection = DetectionOutput.empty;
  UkuranJanjang _ukuran = UkuranJanjang.sedang;
  late int _manualCount; // hasil yang bisa dikoreksi manual oleh user

  @override
  void initState() {
    super.initState();
    _runDetection();
  }

  @override
  void dispose() {
    _blokController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _runDetection() async {
    setState(() => _loading = true);

    _ukuran = await _settings.getDefaultUkuran();
    final occlusion = await _settings.getOcclusionFactor();
    final engine = await _settings.getEngine();

    final bytes = await File(widget.imagePath).readAsBytes();

    DetectionService service = CvDetectionService(occlusionFactor: occlusion);
    String? fallbackNote;

    if (engine == DetectionEngine.tflite) {
      final tflite = TfliteDetectionService();
      try {
        final result = await tflite.detect(imageBytes: bytes, mode: widget.mode);
        setState(() {
          _detection = result;
          _manualCount = widget.mode == ScanMode.janjang
              ? result.visibleCount
              : result.estimatedTotalCount;
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
      _detection = result;
      _manualCount = widget.mode == ScanMode.janjang
          ? result.visibleCount
          : result.estimatedTotalCount;
      _engineUsedFallbackNote = fallbackNote;
      _loading = false;
    });
  }

  GradingResult get _gradingResult => _grading.hitungGrading(
        deteksi: DetectionOutput(
          objects: _detection.objects,
          visibleCount: _detection.visibleCount,
          estimatedTotalCount: _manualCount,
          avgConfidence: _detection.avgConfidence,
        ),
        ukuranJanjang: _ukuran,
      );

  Future<void> _save() async {
    final isBrondol = widget.mode == ScanMode.brondol;
    final grading = isBrondol ? _gradingResult : null;

    final scan = ScanResult(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      imagePath: widget.imagePath,
      mode: widget.mode,
      jumlahJanjang: isBrondol ? 0 : _manualCount,
      estimasiBrondol: isBrondol ? _manualCount : 0,
      ukuranJanjang: _ukuran,
      persenBrondol: grading?.persenBrondol ?? 0,
      fraksi: grading?.fraksi ?? Fraksi.f00,
      blok: _blokController.text.trim(),
      catatan: _catatanController.text.trim(),
    );

    await DatabaseService.instance.insertScan(scan);

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
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(widget.imagePath), fit: BoxFit.cover),
                        CustomPaint(
                          painter: BoundingBoxPainter(
                            objects: _detection.objects,
                            boxColor:
                                isBrondol ? AppColors.accent : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isBrondol
                          ? 'Estimasi brondol: $_manualCount'
                          : 'Jumlah janjang: $_manualCount',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            if (_manualCount > 0) _manualCount--;
                          }),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => _manualCount++),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  'Terdeteksi otomatis: ${_detection.visibleCount} objek '
                  '(confidence rata-rata ${(_detection.avgConfidence * 100).toStringAsFixed(0)}%). '
                  'Koreksi manual jika hasil kurang tepat.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: AppSpacing.md),
                if (isBrondol) ...[
                  const Text('Ukuran Janjang (referensi taksasi)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SegmentedButton<UkuranJanjang>(
                    segments: UkuranJanjang.values
                        .map((u) => ButtonSegment(value: u, label: Text(u.label)))
                        .toList(),
                    selected: {_ukuran},
                    onSelectionChanged: (s) => setState(() => _ukuran = s.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Estimasi Kematangan',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            GradeBadge(fraksi: _gradingResult.fraksi),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_gradingResult.persenBrondol.toStringAsFixed(1)}% brondol '
                          '(dari referensi ${_gradingResult.referensiTotalBrondol} butir/janjang)',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(_gradingResult.fraksi.deskripsi,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
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
}
