import 'package:flutter/material.dart';
import '../models/scan_result.dart';

/// Menggambar kotak hasil deteksi di atas foto (koordinat relatif 0-1).
class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Color boxColor;

  BoundingBoxPainter({required this.objects, this.boxColor = Colors.orange});

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 10,
      backgroundColor: boxColor.withOpacity(0.85),
    );

    for (final obj in objects) {
      final rect = Rect.fromLTWH(
        obj.x * size.width,
        obj.y * size.height,
        obj.width * size.width,
        obj.height * size.height,
      );
      canvas.drawRect(rect, boxPaint);

      final tp = TextPainter(
        text: TextSpan(
            text: '${(obj.confidence * 100).toStringAsFixed(0)}%',
            style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, (rect.top - tp.height).clamp(0, size.height)));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.objects != objects;
  }
}
