import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:yoloeats_app/services/tflite_service.dart';

class DetectionPainter extends CustomPainter {
  final List<Recognition> detections;
  final Size previewSize;
  // TODO: Add Camera Image rotation and camera lens direction if needed for accurate scaling

  DetectionPainter(this.detections, this.previewSize, double scale, double offsetX, double offsetY);

  @override
  void paint(Canvas canvas, Size size) {
    if (previewSize.isEmpty) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red; // Bounding box color

    for (Recognition recognition in detections) {
      final double scaleX = size.width / previewSize.width;
      final double scaleY = size.height / previewSize.height;

      final Rect scaledRect = Rect.fromLTRB(
        recognition.location.left * scaleX,
        recognition.location.top * scaleY,
        recognition.location.right * scaleX,
        recognition.location.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint);

      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: '${recognition.label} ${(recognition.score * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Colors.white,
            backgroundColor: Colors.red.withOpacity(0.7),
            fontSize: 12.0,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(canvas, Offset(scaledRect.left, scaledRect.top - textPainter.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.previewSize != previewSize;
  }
}