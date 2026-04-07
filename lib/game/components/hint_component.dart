import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class HintOutlineComponent extends PositionComponent {
  final double radius;
  final Color hintColor;
  late final Paint _paint;

  HintOutlineComponent({
    required Vector2 position,
    required this.radius,
    required this.hintColor,
  }) : super(position: position) {
    anchor = Anchor.center;
    size = Vector2.all(radius * 2);
    
    _paint = Paint()
      ..color = hintColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // 簡易的な点線描画: 円周を分割して短い円弧を描画する
    int segments = 12;
    double sweepAngle = (2 * pi / segments) * 0.5; // 半分描画、半分休みの点線
    for (int i = 0; i < segments; i++) {
       double startAngle = i * (2 * pi / segments);
       canvas.drawArc(
          Rect.fromCircle(center: Offset(radius, radius), radius: radius),
          startAngle,
          sweepAngle,
          false,
          _paint,
       );
    }
  }
}
