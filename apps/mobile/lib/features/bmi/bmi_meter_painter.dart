import 'dart:math' as math;

import 'package:flutter/material.dart';

class BmiMeterPainter extends CustomPainter {
  const BmiMeterPainter({required this.value, required this.pointerColor});

  final double value;
  final Color pointerColor;

  static const _segments = [
    _BmiSegment(color: Color(0xFF4E8DE6), start: 0.00, end: 0.14),
    _BmiSegment(color: Color(0xFF168878), start: 0.14, end: 0.40),
    _BmiSegment(color: Color(0xFFE0A11B), start: 0.40, end: 0.60),
    _BmiSegment(color: Color(0xFFD65353), start: 0.60, end: 1.00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(12.0, size.width * 0.085);
    final center = Offset(size.width / 2, size.height - stroke * 0.10);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      (size.height - stroke * 0.10) * 2 - stroke,
    );
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = const Color(0xFFE8EFEA);
    canvas.drawArc(rect, startAngle, sweepAngle, false, basePaint);

    for (final segment in _segments) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = segment.color;
      canvas.drawArc(
        rect,
        startAngle + sweepAngle * segment.start,
        sweepAngle * (segment.end - segment.start),
        false,
        paint,
      );
    }

    final tickPaint = Paint()
      ..color = const Color(0xFF9CAAA5)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final radius = rect.width / 2;
    for (final tick in const [0.0, 0.14, 0.40, 0.60, 1.0]) {
      final angle = startAngle + sweepAngle * tick;
      final outer = Offset(
        center.dx + math.cos(angle) * (radius + stroke * 0.20),
        center.dy + math.sin(angle) * (radius + stroke * 0.20),
      );
      final inner = Offset(
        center.dx + math.cos(angle) * (radius - stroke * 0.42),
        center.dy + math.sin(angle) * (radius - stroke * 0.42),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    final clampedValue = value.clamp(0.0, 1.0);
    final angle = startAngle + sweepAngle * clampedValue;
    final pointerEnd = Offset(
      center.dx + math.cos(angle) * (radius - stroke * 0.2),
      center.dy + math.sin(angle) * (radius - stroke * 0.2),
    );

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center.translate(0, 2),
      pointerEnd.translate(0, 2),
      shadowPaint,
    );

    final highlightPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, pointerEnd, highlightPaint);

    final pointerPaint = Paint()
      ..color = pointerColor
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, pointerEnd, pointerPaint);
    canvas.drawCircle(
      center,
      stroke * 0.48,
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );
    canvas.drawCircle(center, stroke * 0.44, Paint()..color = Colors.white);
    canvas.drawCircle(center, stroke * 0.27, Paint()..color = pointerColor);
  }

  @override
  bool shouldRepaint(covariant BmiMeterPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.pointerColor != pointerColor;
  }
}

class _BmiSegment {
  const _BmiSegment({
    required this.color,
    required this.start,
    required this.end,
  });

  final Color color;
  final double start;
  final double end;
}
