import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/scan_result.dart';

/// Satu pilihan kelas objek yang bisa ditandai lewat [BoundingBoxEditor] --
/// dipakai untuk warna kotak & tombol pemilih kelas (mirip
/// MODE_COLOR/MODE_SHORT_LABEL di koreksi.html versi Web).
class BoxClassOption {
  final String label; // nilai yang disimpan di DetectedObject.label
  final String displayName;
  final String shortName; // dipakai di chip daftar kotak (ringkas)
  final Color color;

  const BoxClassOption({
    required this.label,
    required this.displayName,
    required this.shortName,
    required this.color,
  });
}

/// Konfirmasi tandan/kotak hasil tag manual dianggap 100% pasti (bukan hasil
/// model) -- sama seperti kotak manual di koreksi.html Web.
const double kManualBoxConfidence = 1.0;

const double _kHandleRadius = 12;
const double _kMinBoxSizeFraction = 0.01; // buang drag super kecil (kesalahan tap)

enum _DragMode { none, draw, move, resizeTL, resizeTR, resizeBL, resizeBR }

/// Editor kotak interaktif di atas sebuah foto -- padanan langsung dari
/// canvas box editor di koreksi.html (Web): tap-drag di area kosong untuk
/// menggambar kotak baru (kelas sesuai [activeClass] yang sedang dipilih),
/// tap sebuah kotak untuk memilihnya (muncul gagang di 4 sudut untuk
/// resize + badge "x" untuk hapus), drag badan kotak untuk menggeser.
///
/// Semua koordinat kotak REL (0-1) terhadap ukuran foto ASLI (sama seperti
/// [DetectedObject] & format yang sudah dipakai TfliteDetectionService/
/// CvDetectionService) -- supaya hasil edit di sini bisa langsung dipakai
/// untuk hitung ulang jumlah Janjang/Brondol/Janjang Kosong & disimpan,
/// tanpa konversi tambahan.
///
/// Widget ini MENGATUR aspect ratio-nya SENDIRI mengikuti ukuran asli foto
/// (bukan dipatok 4:3 oleh pemanggil) -- supaya kotak yang digambar presisi
/// pas menutup objeknya, tidak melenceng akibat foto ter-crop/stretch.
class BoundingBoxEditor extends StatefulWidget {
  final ImageProvider image;
  final List<DetectedObject> boxes;
  final ValueChanged<List<DetectedObject>> onChanged;
  final List<BoxClassOption> classOptions;
  final String activeClass;
  final ValueChanged<String>? onActiveClassChanged;

  /// Tampilkan baris tombol pemilih kelas di atas foto. Matikan kalau
  /// pemanggil sudah punya UI sendiri untuk memilih [activeClass].
  final bool showClassPicker;

  /// Tampilkan daftar chip kotak (mirip "Kotak di Foto Ini" di Web) di
  /// bawah foto -- membantu memilih/menghapus kotak kecil yang susah
  /// disentuh langsung di foto.
  final bool showBoxList;

  const BoundingBoxEditor({
    super.key,
    required this.image,
    required this.boxes,
    required this.onChanged,
    required this.classOptions,
    required this.activeClass,
    this.onActiveClassChanged,
    this.showClassPicker = true,
    this.showBoxList = true,
  });

  @override
  State<BoundingBoxEditor> createState() => _BoundingBoxEditorState();
}

class _BoundingBoxEditorState extends State<BoundingBoxEditor> {
  double? _imageAspectRatio; // width / height, diisi setelah dimensi foto diketahui
  ImageStream? _imageStream;
  late ImageStreamListener _imageStreamListener;

  int? _selectedIdx;
  _DragMode _dragMode = _DragMode.none;
  Offset? _dragStartLocal; // posisi pointer (px lokal) saat pan dimulai
  Rect? _dragOrigRectFrac; // rect kotak (fraksi 0-1) sebelum drag ini dimulai
  Rect? _drawingRectFrac; // kotak yang sedang digambar baru (belum ditambahkan ke list)

  @override
  void initState() {
    super.initState();
    _imageStreamListener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (!mounted || h <= 0) return;
      setState(() => _imageAspectRatio = w / h);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant BoundingBoxEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _imageAspectRatio = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final newStream = widget.image.resolve(createLocalImageConfiguration(context));
    if (newStream.key == _imageStream?.key) return;
    _imageStream?.removeListener(_imageStreamListener);
    _imageStream = newStream;
    _imageStream!.addListener(_imageStreamListener);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    super.dispose();
  }

  BoxClassOption _optionFor(String label) {
    final match = widget.classOptions.where((c) => c.label == label);
    if (match.isNotEmpty) return match.first;
    return BoxClassOption(
      label: label,
      displayName: label,
      shortName: label,
      color: Colors.blueGrey,
    );
  }

  void _emit(List<DetectedObject> next) => widget.onChanged(next);

  void _deleteSelected() {
    if (_selectedIdx == null) return;
    final next = List<DetectedObject>.from(widget.boxes)..removeAt(_selectedIdx!);
    setState(() => _selectedIdx = null);
    _emit(next);
  }

  void _reclassifySelected(String newLabel) {
    if (_selectedIdx == null) return;
    final next = List<DetectedObject>.from(widget.boxes);
    next[_selectedIdx!] = next[_selectedIdx!].copyWith(label: newLabel);
    _emit(next);
  }

  Rect _rectOf(DetectedObject b) => Rect.fromLTWH(b.x, b.y, b.width, b.height);

  Offset _toFrac(Offset localPx, Size canvasPx) =>
      Offset(localPx.dx / canvasPx.width, localPx.dy / canvasPx.height);

  /// Cari handle sudut kotak terpilih yang paling dekat dengan [localPx],
  /// null kalau tidak ada yang cukup dekat (dalam radius sentuh).
  _DragMode? _hitHandle(Offset localPx, Size canvasPx) {
    if (_selectedIdx == null) return null;
    final r = _rectOf(widget.boxes[_selectedIdx!]);
    final corners = <_DragMode, Offset>{
      _DragMode.resizeTL: Offset(r.left * canvasPx.width, r.top * canvasPx.height),
      _DragMode.resizeTR: Offset(r.right * canvasPx.width, r.top * canvasPx.height),
      _DragMode.resizeBL: Offset(r.left * canvasPx.width, r.bottom * canvasPx.height),
      _DragMode.resizeBR: Offset(r.right * canvasPx.width, r.bottom * canvasPx.height),
    };
    for (final entry in corners.entries) {
      if ((entry.value - localPx).distance <= _kHandleRadius * 1.8) return entry.key;
    }
    return null;
  }

  /// Cari index kotak (dicek dari yang paling AKHIR/atas dulu, sesuai urutan
  /// gambar) yang memuat titik [localPx]. Null kalau tidak ada.
  int? _hitBox(Offset localPx, Size canvasPx) {
    final frac = _toFrac(localPx, canvasPx);
    for (int i = widget.boxes.length - 1; i >= 0; i--) {
      if (_rectOf(widget.boxes[i]).contains(frac)) return i;
    }
    return null;
  }

  void _onPanStart(DragStartDetails details, Size canvasPx) {
    final local = details.localPosition;

    final handle = _hitHandle(local, canvasPx);
    if (handle != null) {
      _dragMode = handle;
      _dragStartLocal = local;
      _dragOrigRectFrac = _rectOf(widget.boxes[_selectedIdx!]);
      return;
    }

    final hitIdx = _hitBox(local, canvasPx);
    if (hitIdx != null) {
      setState(() => _selectedIdx = hitIdx);
      _dragMode = _DragMode.move;
      _dragStartLocal = local;
      _dragOrigRectFrac = _rectOf(widget.boxes[hitIdx]);
      return;
    }

    // Area kosong -- mulai gambar kotak baru dengan kelas aktif.
    setState(() => _selectedIdx = null);
    _dragMode = _DragMode.draw;
    _dragStartLocal = local;
    final f = _toFrac(local, canvasPx);
    _drawingRectFrac = Rect.fromLTWH(f.dx, f.dy, 0, 0);
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasPx) {
    if (_dragMode == _DragMode.none || _dragStartLocal == null) return;
    final local = details.localPosition;

    if (_dragMode == _DragMode.draw) {
      final start = _toFrac(_dragStartLocal!, canvasPx);
      final cur = _toFrac(local, canvasPx);
      setState(() {
        _drawingRectFrac = Rect.fromPoints(start, cur);
      });
      return;
    }

    if (_selectedIdx == null || _dragOrigRectFrac == null) return;
    final deltaPx = local - _dragStartLocal!;
    final deltaFrac = Offset(deltaPx.dx / canvasPx.width, deltaPx.dy / canvasPx.height);
    final orig = _dragOrigRectFrac!;
    Rect next = orig;

    switch (_dragMode) {
      case _DragMode.move:
        next = orig.shift(deltaFrac);
        break;
      case _DragMode.resizeTL:
        next = Rect.fromLTRB(orig.left + deltaFrac.dx, orig.top + deltaFrac.dy, orig.right, orig.bottom);
        break;
      case _DragMode.resizeTR:
        next = Rect.fromLTRB(orig.left, orig.top + deltaFrac.dy, orig.right + deltaFrac.dx, orig.bottom);
        break;
      case _DragMode.resizeBL:
        next = Rect.fromLTRB(orig.left + deltaFrac.dx, orig.top, orig.right, orig.bottom + deltaFrac.dy);
        break;
      case _DragMode.resizeBR:
        next = Rect.fromLTRB(orig.left, orig.top, orig.right + deltaFrac.dx, orig.bottom + deltaFrac.dy);
        break;
      default:
        break;
    }

    // Jaga kotak tetap di dalam foto (0-1) & tidak terbalik (width/height negatif).
    next = Rect.fromLTRB(
      next.left.clamp(0.0, 1.0),
      next.top.clamp(0.0, 1.0),
      next.right.clamp(0.0, 1.0),
      next.bottom.clamp(0.0, 1.0),
    );
    if (next.width <= 0 || next.height <= 0) return;

    final list = List<DetectedObject>.from(widget.boxes);
    list[_selectedIdx!] = list[_selectedIdx!].copyWith(
      x: next.left,
      y: next.top,
      width: next.width,
      height: next.height,
    );
    _emit(list);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragMode == _DragMode.draw && _drawingRectFrac != null) {
      final r = _drawingRectFrac!;
      final normalized = Rect.fromLTRB(
        r.left.clamp(0.0, 1.0).toDouble(),
        r.top.clamp(0.0, 1.0).toDouble(),
        r.right.clamp(0.0, 1.0).toDouble(),
        r.bottom.clamp(0.0, 1.0).toDouble(),
      );
      final w = normalized.width.abs();
      final h = normalized.height.abs();
      if (w >= _kMinBoxSizeFraction && h >= _kMinBoxSizeFraction) {
        final rect = Rect.fromLTRB(
          normalized.left < normalized.right ? normalized.left : normalized.right,
          normalized.top < normalized.bottom ? normalized.top : normalized.bottom,
          normalized.left < normalized.right ? normalized.right : normalized.left,
          normalized.top < normalized.bottom ? normalized.bottom : normalized.top,
        );
        final newBox = DetectedObject(
          label: widget.activeClass,
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
          confidence: kManualBoxConfidence,
        );
        final next = List<DetectedObject>.from(widget.boxes)..add(newBox);
        setState(() {
          _selectedIdx = next.length - 1;
          _drawingRectFrac = null;
        });
        _emit(next);
      } else {
        setState(() => _drawingRectFrac = null);
      }
    }
    _dragMode = _DragMode.none;
    _dragStartLocal = null;
    _dragOrigRectFrac = null;
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _imageAspectRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showClassPicker) _buildClassPicker(),
        if (widget.showClassPicker) const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: aspect ?? (4 / 3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: aspect == null
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasPx = Size(constraints.maxWidth, constraints.maxHeight);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(image: widget.image, fit: BoxFit.fill),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (d) => _onPanStart(d, canvasPx),
                            onPanUpdate: (d) => _onPanUpdate(d, canvasPx),
                            onPanEnd: _onPanEnd,
                            child: CustomPaint(
                              painter: _EditorPainter(
                                boxes: widget.boxes,
                                selectedIdx: _selectedIdx,
                                drawingRectFrac: _drawingRectFrac,
                                activeClassColor: _optionFor(widget.activeClass).color,
                                colorFor: (label) => _optionFor(label).color,
                              ),
                            ),
                          ),
                          if (_selectedIdx != null && _selectedIdx! < widget.boxes.length)
                            _buildDeleteBadge(canvasPx),
                        ],
                      );
                    },
                  ),
          ),
        ),
        if (_selectedIdx != null && _selectedIdx! < widget.boxes.length) ...[
          const SizedBox(height: 8),
          _buildSelectedToolbar(),
        ],
        if (widget.showBoxList) ...[
          const SizedBox(height: 8),
          _buildBoxList(),
        ],
      ],
    );
  }

  Widget _buildDeleteBadge(Size canvasPx) {
    final r = _rectOf(widget.boxes[_selectedIdx!]);
    final left = (r.right * canvasPx.width - 14).clamp(0.0, canvasPx.width - 28);
    final top = (r.top * canvasPx.height - 14).clamp(0.0, canvasPx.height - 28);
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: _deleteSelected,
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildClassPicker() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: widget.classOptions.map((opt) {
        final isActive = opt.label == widget.activeClass;
        return ChoiceChip(
          label: Text(opt.displayName),
          selected: isActive,
          selectedColor: opt.color.withOpacity(0.85),
          labelStyle: TextStyle(
            color: isActive ? Colors.white : Colors.black87,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          onSelected: (_) => widget.onActiveClassChanged?.call(opt.label),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedToolbar() {
    final selected = widget.boxes[_selectedIdx!];
    return Row(
      children: [
        const Text('Kelas kotak ini:', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 4,
            children: widget.classOptions.map((opt) {
              final isActive = opt.label == selected.label;
              return ChoiceChip(
                label: Text(opt.shortName, style: const TextStyle(fontSize: 11)),
                selected: isActive,
                selectedColor: opt.color.withOpacity(0.85),
                labelStyle: TextStyle(color: isActive ? Colors.white : Colors.black87),
                onSelected: (_) => _reclassifySelected(opt.label),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          tooltip: 'Hapus kotak ini',
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildBoxList() {
    if (widget.boxes.isEmpty) {
      return const Text(
        'Belum ada kotak. Gambar langsung di foto (tekan & seret) untuk menandai objek yang belum tertangkap.',
        style: TextStyle(fontSize: 11, color: Colors.black45),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(widget.boxes.length, (i) {
        final b = widget.boxes[i];
        final opt = _optionFor(b.label);
        final isSelected = i == _selectedIdx;
        return GestureDetector(
          onTap: () => setState(() => _selectedIdx = i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? opt.color.withOpacity(0.18) : Colors.transparent,
              border: Border.all(color: opt.color, width: isSelected ? 1.6 : 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${i + 1}. ${opt.shortName}',
              style: TextStyle(fontSize: 11, color: opt.color, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }),
    );
  }
}

class _EditorPainter extends CustomPainter {
  final List<DetectedObject> boxes;
  final int? selectedIdx;
  final Rect? drawingRectFrac;
  final Color activeClassColor;
  final Color Function(String label) colorFor;

  _EditorPainter({
    required this.boxes,
    required this.selectedIdx,
    required this.drawingRectFrac,
    required this.activeClassColor,
    required this.colorFor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      final color = colorFor(b.label);
      final selected = i == selectedIdx;
      final rect = Rect.fromLTWH(
        b.x * size.width,
        b.y * size.height,
        b.width * size.width,
        b.height * size.height,
      );

      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.5 : 2;
      canvas.drawRect(rect, boxPaint);

      final confPct = (b.confidence * 100).round();
      final label = '${i + 1} $confPct%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white, fontSize: 11, backgroundColor: color.withOpacity(0.85)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, (rect.top - tp.height).clamp(0, size.height - tp.height)));

      if (selected) {
        final handlePaint = Paint()..color = Colors.white;
        final handleStroke = Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
          canvas.drawCircle(corner, _kHandleRadius * 0.55, handlePaint);
          canvas.drawCircle(corner, _kHandleRadius * 0.55, handleStroke);
        }
      }
    }

    if (drawingRectFrac != null) {
      final r = drawingRectFrac!;
      final rect = Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      );
      final dashPaint = Paint()
        ..color = activeClassColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRect(rect, dashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) {
    return oldDelegate.boxes != boxes ||
        oldDelegate.selectedIdx != selectedIdx ||
        oldDelegate.drawingRectFrac != drawingRectFrac;
  }
}
