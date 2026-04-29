import 'package:flutter/material.dart';
import '../../data/models/game_item.dart';

class StampWidget extends StatefulWidget {
  const StampWidget({
    super.key,
    required this.item,
    this.level = 1,
    this.forceLarge = false,
  });

  final GameItem item;
  final int level;
  final bool forceLarge; // Use for center overlay pops in GameScreen

  @override
  State<StampWidget> createState() => _StampWidgetState();
}

class _StampWidgetState extends State<StampWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.level >= 4) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(StampWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.level >= 4 && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (widget.level < 4 && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor(String? colorName) {
    switch (colorName) {
      case 'Cyan':
        return Colors.cyanAccent;
      case 'Blue':
        return Colors.blueAccent;
      case 'Red':
        return Colors.redAccent;
      case 'Yellow':
        return Colors.amberAccent;
      case 'Magenta':
        return Colors.pinkAccent;
      case 'Purple':
        return Colors.deepPurpleAccent;
      default:
        return Colors.white;
    }
  }

  IconData _getIcon(String? iconName) {
    switch (iconName) {
      case 'handshake':
        return Icons.handshake;
      case 'water_drop':
        return Icons.water_drop;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'thumb_up':
        return Icons.thumb_up;
      case 'coffee':
        return Icons.coffee;
      case 'visibility':
        return Icons.visibility;
      case 'memory':
        return Icons.memory;
      default:
        return Icons.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.item.text ?? '...';
    final color = _getColor(widget.item.colorName);
    final iconData = _getIcon(widget.item.iconName);

    final double scale = widget.forceLarge ? 2.0 : 1.0;

    // Lv 1: White text only
    if (widget.level <= 1) {
      return Text(
        text,
        softWrap: false,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14 * scale,
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.white54, blurRadius: 2)],
        ),
      );
    }

    // Lv 2: Color text + Glow
    if (widget.level == 2) {
      return Text(
        text,
        softWrap: false,
        style: TextStyle(
          color: color,
          fontSize: 16 * scale,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(color: color, blurRadius: 10 * scale),
            Shadow(color: Colors.white, blurRadius: 2 * scale),
          ],
        ),
      );
    }

    // Lv 3 and Lv 4: Icon + Text + Glow + Animation
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          iconData,
          color: color,
          size: 20 * scale,
          shadows: [Shadow(color: color, blurRadius: 12 * scale)],
        ),
        SizedBox(width: 8 * scale),
        Text(
          text,
          softWrap: false,
          style: TextStyle(
            color: color,
            fontSize: 18 * scale,
            fontFamily: 'Courier',
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: color, blurRadius: 12 * scale),
              Shadow(color: Colors.white, blurRadius: 2 * scale),
            ],
          ),
        ),
      ],
    );

    if (widget.level == 3) {
      return content;
    }

    // Lv 4: Breathing Animation
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glowScale = 1.0 + (_controller.value * 0.15); // Scale 1.0 to 1.15
        final opacity = 0.6 + (_controller.value * 0.4); // Opacity 0.6 to 1.0

        return Transform.scale(
          scale: glowScale,
          child: Opacity(
            opacity: opacity,
            child: content,
          ),
        );
      },
    );
  }
}
