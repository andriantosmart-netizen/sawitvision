import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/scan_result.dart';
import '../utils/constants.dart';

/// Layar kamera LIVE -- HANYA untuk preview/framing & jepret foto.
///
/// CATATAN PERUBAHAN (setelah dicoba langsung di HP): versi awal layar ini
/// menjalankan deteksi TFLite otomatis tiap 2 detik + izin tap-tag SELAGI
/// preview masih terbuka. Di percobaan nyata itu terasa LAG & sulit dipakai
/// (ambil sampel foto berkala + jalankan model tiap 2 detik cukup berat
/// untuk berjalan mulus di belakang preview kamera). Sesuai masukan user,
/// semua proses deteksi & koreksi kotak SEKARANG DIPINDAH SEPENUHNYA ke
/// [ResultScreen] (sesudah jepret) -- kamera di sini murni viewfinder +
/// tombol jepret, TIDAK ADA proses berat apapun yang berjalan selagi
/// preview terbuka, supaya preview-nya tetap mulus.
class LiveCameraScreen extends StatefulWidget {
  final ScanMode mode;
  const LiveCameraScreen({super.key, required this.mode});

  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  String? _permissionError;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xfile = await controller.takePicture();
      if (!mounted) return;
      // Tidak lagi mengirim 'initialBoxes' -- ResultScreen yang menjalankan
      // deteksi dari foto final (sama seperti jalur "Pilih dari Galeri"),
      // lalu semua koreksi kotak dilakukan di sana lewat BoundingBoxEditor.
      await Navigator.pushNamed(context, '/result', arguments: {
        'imagePath': xfile.path,
        'mode': widget.mode,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
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
              const Text(
                'Sementara itu Anda tetap bisa pakai "Pilih dari Galeri" di layar sebelumnya.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
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
              child: CameraPreview(controller),
            ),
          ),
        ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Foto akan diproses & bisa dikoreksi (tambah/geser/resize/hapus '
                'kotak) di layar berikutnya setelah jepret.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 68,
                  height: 68,
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
