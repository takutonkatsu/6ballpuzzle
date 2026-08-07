import 'package:flutter/material.dart';

import '../../data/models/game_item.dart';
import '../theme/game_theme_colors.dart';

class StampWidget extends StatefulWidget {
  const StampWidget({
    super.key,
    required this.item,
    this.level = 1,
    this.forceLarge = false,
    this.colorOverride,
  });

  final GameItem item;
  final int level;
  final bool forceLarge;
  final Color? colorOverride;

  @override
  State<StampWidget> createState() => _StampWidgetState();
}

class _StampWidgetState extends State<StampWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
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
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor(String? colorName) {
    return switch (colorName) {
      'Cyan' => Colors.cyanAccent,
      'Blue' => Colors.blueAccent,
      'Red' => Colors.redAccent,
      'Yellow' => Colors.amberAccent,
      'Magenta' => Colors.pinkAccent,
      'Purple' => Colors.deepPurpleAccent,
      'Green' => GameThemeColors.endless,
      _ => Colors.white,
    };
  }

  IconData _getIcon(String? iconName) {
    return switch (iconName) {
      'handshake' => Icons.handshake,
      'water_drop' => Icons.water_drop,
      'local_fire_department' => Icons.local_fire_department,
      'thumb_up' => Icons.thumb_up,
      'coffee' => Icons.coffee,
      'visibility' => Icons.visibility,
      'memory' => Icons.memory,
      _ => Icons.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.item.text ?? '...';
    final glowColor = _getColor(widget.item.colorName);
    final iconName = widget.item.iconName;
    final iconData = iconName == null ? null : _getIcon(iconName);
    final scale = widget.forceLarge ? 2.0 : 1.0;
    final level = widget.level.clamp(1, GameItem.maxStampLevel);

    final fontSize = switch (level) {
      1 => 14.0,
      2 => 14.0,
      3 => 18.5,
      _ => 19.0,
    };
    final textColor = level <= 1 ? Colors.white : glowColor;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (iconData != null) ...[
          Icon(
            iconData,
            color: textColor,
            size: (level >= 3 ? 20 : 17) * scale,
          ),
          SizedBox(width: 6 * scale),
        ],
        Text(
          text,
          softWrap: false,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize * scale,
            fontFamily: 'Courier',
            fontWeight: level <= 1 ? FontWeight.bold : FontWeight.w900,
            letterSpacing: level >= 3 ? 0.4 * scale : 0,
          ),
        ),
      ],
    );

    if (level < 4) {
      return content;
    }

    return AnimatedBuilder(
      animation: _controller,
      child: content,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(0, -4.4 * scale * t),
          child: Transform.rotate(
            angle: 0.07 * scale * (t - 0.5),
            child: Transform.scale(
              scale: 1.0 + 0.16 * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
