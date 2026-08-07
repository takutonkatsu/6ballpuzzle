import 'package:flutter/material.dart';

class GamePressable extends StatefulWidget {
  const GamePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.borderRadius,
    this.enabled = true,
    this.scaleDown = 0.94,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onTapDown;
  final VoidCallback? onTapUp;
  final VoidCallback? onTapCancel;
  final BorderRadius? borderRadius;
  final bool enabled;
  final double scaleDown;
  final String? semanticLabel;

  @override
  State<GamePressable> createState() => _GamePressableState();
}

class _GamePressableState extends State<GamePressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 92),
    reverseDuration: const Duration(milliseconds: 170),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: widget.scaleDown)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 48,
    ),
    TweenSequenceItem(
      tween: Tween(begin: widget.scaleDown, end: 1.025)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 32,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.025, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 20,
    ),
  ]).animate(_controller);

  bool _pressed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pressDown() {
    if (!widget.enabled) {
      return;
    }
    _pressed = true;
    _controller.value = 0.0;
    _controller.animateTo(0.48);
    widget.onTapDown?.call();
  }

  void _pressUp({required bool invokeTap}) {
    if (!_pressed) {
      return;
    }
    _pressed = false;
    _controller.forward(from: 0.48);
    widget.onTapUp?.call();
    if (invokeTap) {
      widget.onTap?.call();
    }
  }

  void _cancel() {
    if (!_pressed) {
      return;
    }
    _pressed = false;
    _controller.reverse();
    widget.onTapCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = _pressed ? 0.12 : 0.0;
        return Transform.scale(
          scale: _scale.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: glow <= 0
                  ? const []
                  : [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: glow),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => _pressDown() : null,
        onTapUp: widget.enabled ? (_) => _pressUp(invokeTap: true) : null,
        onTapCancel: widget.enabled ? _cancel : null,
        child: content,
      ),
    );
  }
}
