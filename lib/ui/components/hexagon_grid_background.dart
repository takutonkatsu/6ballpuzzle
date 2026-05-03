import 'dart:math' as math;

import 'package:flutter/material.dart';

class HexagonGridBackground extends StatelessWidget {
  const HexagonGridBackground({
    super.key,
    this.color = Colors.cyanAccent,
    this.opacity = 0.045,
    this.hexRadius = 26,
  });

  final Color color;
  final double opacity;
  final double hexRadius;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: CustomPaint(
            painter: _HexagonGridPainter(
              color: color,
              hexRadius: hexRadius,
            ),
          ),
        ),
      ),
    );
  }
}

class _HexagonGridPainter extends CustomPainter {
  const _HexagonGridPainter({
    required this.color,
    required this.hexRadius,
  });

  final Color color;
  final double hexRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final width = math.sqrt(3) * hexRadius;
    final verticalStep = hexRadius * 1.5;
    final path = Path();

    for (double y = -hexRadius;
        y < size.height + hexRadius;
        y += verticalStep) {
      final row = (y / verticalStep).round();
      final xOffset = row.isEven ? 0.0 : width / 2;
      for (double x = -width; x < size.width + width; x += width) {
        _addHexagon(path, Offset(x + xOffset, y), hexRadius);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _addHexagon(Path path, Offset center, double radius) {
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
  }

  @override
  bool shouldRepaint(covariant _HexagonGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.hexRadius != hexRadius;
  }
}
