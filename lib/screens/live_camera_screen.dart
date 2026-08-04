import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/scan_result.dart';
import '../services/settings_service.dart';
import '../services/tflite_detection_service.dart';
import '../utils/constants.dart';
import '../widgets/bounding_box_editor.dart'
    show BoxClassOption, kManualBoxConfidence;

/// Layar kamera LIVE (preview real-time) yang menggantikan kamera bawaan HP
/// (sebelumnya dipakai lewat `image_picker`, lihat komentar lama di
/// scan_screen.dart). Menjalankan deteksi YOLO26n secara berkala SELAGI
/// preview masih terbuka supaya kotak yang sudah tertangkap kelihatan
/// langsung, dan mengizinkan user KETUK area yang belum tertandai untuk
/// menambah kotak sebelum jepret -- persis permintaan "BB dibentuk saat
/// kamera masih terbuka... apabila ada yang tidak tertandai bisa langsung
/// di tag".
///
/// CATATAN JUJUR SOAL PENDEKATAN TEKNIS (supaya tidak jadi kejutan kalau
/// hasilnya beda dari bayangan "live" yang mulus):
/// - Deteksi berkala di sini dijalankan dengan mengambil FOTO JPEG kecil
///   berkala (bukan memproses raw camera frame stream) lalu dilewatkan ke
///   TfliteDetectionService yang sama dipakai di layar hasil. Ini SENGAJA
///   dipilih dibanding memproses frame mentah (`CameraImage`/YUV) karena
///   konversi format YUV->RGB manual berisiko salah & tidak bisa saya
///   uji langsung di lingkungan kerja saya (tidak ada SDK Flutter/HP
///   fisik) -- kalau ternyata kedip/jeda tiap ambil sampel terasa
///   mengganggu di lapangan, beri tahu supaya bisa dioptimasi lebih lanjut
///   (mis. pindah ke image stream + isolate).
/// - Kotak yang ditambah lewat TAP di sini dibuat ukuran default (bukan
///   gambar-drag bebas, karena preview terus berubah/refresh) -- posisi &
///   ukurannya bisa dirapikan lagi nanti di layar hasil (BoundingBoxEditor
///   penuh, dengan gambar-drag & resize) sebelum disimpan.
/// - Koordinat kotak (baik hasil deteksi live maupun tap manual) memakai
///   fraksi (0-1) relatif ke area PREVIEW -- dibawa apa adanya ke foto hasil
///   jepretan (asumsi framing preview & hasil jepretan sama), lalu tetap
///   bisa dikoreksi presisi di layar hasil kalau ada pergeseran kecil.
class LiveCameraScreen extends StatefulWidget {
  final ScanMode mode;
  const LiveCameraScreen({super.key, required this.mode});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  final _settings = SettingsService();

  CameraController? _controller;
  Future<void>? _initFuture;
  String? _permissionError;

  final List<DetectedObject> _liveBoxes = [];
  bool _scanning = false;
  bool _capturing = false;
  Timer? _scanTimer;
  String _activeTapClass = 'janjang';

  static const _scanInterval = Duration(seconds: 2);

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeTapClass = widget.mode == ScanMode.brondol ? 'brondol' : 'janjang';
    _initFuture = _setup();
  }

  Future<void> _setup() async {
    // Reset pesan error lama -- penting untuk jalur "resume dari background"
    // (didChangeAppLifecycleState) yang memanggil _setup() ulang; tanpa ini
    // pesan error izin/kamera yang lama akan tetap tampil walau percobaan
    // baru ini berhasil.
    _permissionError = null;
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _permissionError =
          'Izin kamera ditolak. Aktifkan lewat Pengaturan HP > Aplikasi > SawitVision > Izin, lalu buka lagi layar ini.');
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _permissionError = 'Tidak ada kamera yang terdeteksi di perangkat ini.');
      return;
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await controller.initialize();
    if (!mounted) return;
    setState(() {});
    _startPeriodicScan();
  }

  void _startPeriodicScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(_scanInterval, (_) => _runLiveScan());
  }

  Future<void> _runLiveScan() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_scanning || _capturing) return; // jangan tumpuk permintaan
    _scanning = true;
    try {
      final confidence = await _settings.getTfliteConfidenceThreshold();
      final xfile = await controller.takePicture();
      final bytes = await File(xfile.path).readAsBytes();
      final service = TfliteDetectionService(confidenceThreshold: confidence);
      final result = await service.detect(imageBytes: bytes, mode: widget.mode);
      // Hapus file sementara hasil sampel live -- bukan foto final, tidak
      // perlu disimpan (foto final diambil ulang saat tombol jepret ditekan).
      unawaited(File(xfile.path).delete().catchError((_) => File(xfile.path)));
      if (!mounted) return;
      setState(() {
        _liveBoxes
          ..clear()
          ..addAll(result.objects);
      });
    } catch (e) {
      // Contoh error umum: ModelNotAvailableException kalau engine belum
      // TFLite/model belum ada -- diamkan saja di live-scan (bukan fatal),
      // user tetap bisa jepret & tag manual seperti biasa.
      debugPrint('Live scan gagal (diabaikan, tidak fatal): $e');
    } finally {
      _scanning = false;
    }
  }

  void _onTapAdd(Offset localFrac) {
    const defaultSize = 0.14;
    final x = (localFrac.dx - defaultSize / 2).clamp(0.0, 1.0 - defaultSize);
    final y = (localFrac.dy - defaultSize / 2).clamp(0.0, 1.0 - defaultSize);
    setState(() {
      _liveBoxes.add(DetectedObject(
        label: _activeTapClass,
        x: x,
        y: y,
        width: defaultSize,
        height: defaultSize,
        confidence: kManualBoxConfidence,
      ));
    });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    _scanTimer?.cancel();
    try {
      final xfile = await controller.takePicture();
      if (!mounted) return;
      await Navigator.pushNamed(context, '/result', arguments: {
        'imagePath': xfile.path,
        'mode': widget.mode,
        'initialBoxes': List<DetectedObject>.from(_liveBoxes),
      });
      if (!mounted) return;
      // Sesudah kembali dari layar hasil (mis. user tekan back tanpa
      // simpan), lanjutkan live-scan lagi supaya bisa coba jepret ulang.
      _liveBoxes.clear();
      _startPeriodicScan();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
      _startPeriodicScan();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _scanTimer?.cancel();
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initFuture = _setup();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Kamera — ${widget.mode.label}'),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (_permissionError != null) {
            return _buildMessage(_permissionError!, showGalleryHint: true);
          }
          if (snapshot.connectionState != ConnectionState.done ||
              _controller == null ||
              !_controller!.value.isInitialized) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          return _buildCameraBody();
        },
      ),
    );
  }

  Widget _buildMessage(String message, {bool showGalleryHint = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            if (showGalleryHint) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sementara itu Anda tetap bisa pakai "Pilih dari Galeri" di layar sebelumnya.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBody() {
    final controller = _controller!;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1 / controller.value.aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTapAdd(
                          Offset(
                            d.localPosition.dx / canvasSize.width,
                            d.localPosition.dy / canvasSize.height,
                          ),
                        ),
                        child: CustomPaint(
                          painter: _LiveOverlayPainter(
                            boxes: _liveBoxes,
                            colorFor: (label) => _classOptions
                                .firstWhere(
                                  (c) => c.label == label,
                                  orElse: () => _classOptions.first,
                                )
                                .color,
                          ),
                        ),
                      ),
                      if (_scanning)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: _ScanningBadge(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ketuk area yang belum tertandai untuk menambah kotak (kelas: ${_classOptions.firstWhere((c) => c.label == _activeTapClass).displayName}). Rapikan lagi setelah jepret.',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                alignment: WrapAlignment.center,
                children: _classOptions.map((opt) {
                  final active = opt.label == _activeTapClass;
                  return ChoiceChip(
                    label: Text(opt.displayName, style: const TextStyle(fontSize: 11)),
                    selected: active,
                    selectedColor: opt.color,
                    backgroundColor: Colors.white12,
                    labelStyle: TextStyle(color: active ? Colors.white : Colors.white70),
                    onSelected: (_) => setState(() => _activeTapClass = opt.label),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                '${_liveBoxes.length} kotak siap dibawa ke layar hasil',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 68,
                  height: 68,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white38, width: 4),
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt, color: Colors.black87, size: 30),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanningBadge extends StatelessWidget {
  const _ScanningBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
          ),
          SizedBox(width: 6),
          Text('memindai...', style: TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

class _LiveOverlayPainter extends CustomPainter {
  final List<DetectedObject> boxes;
  final Color Function(String label) colorFor;

  _LiveOverlayPainter({required this.boxes, required this.colorFor});

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final color = colorFor(b.label);
      final rect = Rect.fromLTWH(
        b.x * size.width,
        b.y * size.height,
        b.width * size.width,
        b.height * size.height,
      );
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveOverlayPainter oldDelegate) => oldDelegate.boxes != boxes;
}
