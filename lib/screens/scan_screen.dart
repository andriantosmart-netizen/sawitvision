import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan_result.dart';
import '../utils/constants.dart';
import 'live_camera_screen.dart';

/// Layar untuk mengambil foto (kamera live atau galeri) sebelum diproses
/// oleh mesin deteksi di [ResultScreen].
///
/// "Ambil Foto" membuka [LiveCameraScreen] (preview real-time + deteksi
/// berkala + tag manual sebelum jepret). "Pilih dari Galeri" tetap memakai
/// `image_picker` seperti sebelumnya -- untuk foto yang sudah ada, deteksi
/// otomatis tetap jalan di [ResultScreen] seperti biasa, hanya saja tanpa
/// kesempatan menandai langsung sebelum jepret.
class ScanScreen extends StatefulWidget {
  final ScanMode mode;
  const ScanScreen({super.key, required this.mode});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _pickFromGallery() async {
    setState(() => _busy = true);
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (xfile == null) {
        setState(() => _busy = false);
        return;
      }
      if (!mounted) return;
      await Navigator.pushNamed(context, '/result', arguments: {
        'imagePath': xfile.path,
        'mode': widget.mode,
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openLiveCamera() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LiveCameraScreen(mode: widget.mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBrondol = widget.mode == ScanMode.brondol;
    return Scaffold(
      appBar: AppBar(title: Text(widget.mode.label)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isBrondol ? Icons.grain : Icons.eco,
                size: 80,
                color: isBrondol ? AppColors.accent : AppColors.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isBrondol
                  ? 'Foto tumpukan/serakan brondol dari atas dengan pencahayaan cukup. '
                      'Usahakan seluruh tumpukan masuk dalam bingkai.'
                  : 'Foto tumpukan janjang (TBS) di TPH. Usahakan setiap tandan '
                      'terlihat jelas dan tidak terlalu bertumpuk.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_busy)
              const CircularProgressIndicator()
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Ambil Foto'),
                  onPressed: _openLiveCamera,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Pilih dari Galeri'),
                  onPressed: _pickFromGallery,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
