import 'package:flutter/material.dart';

import '../../data/models/game_item.dart';
import '../theme/game_theme_colors.dart';
import 'stamp_widget.dart';

class StampSquareTile extends StatelessWidget {
  const StampSquareTile({
    super.key,
    this.item,
    this.level,
    this.onTap,
    this.selected = false,
    this.available = true,
    this.showLevel = false,
    this.emptyLabel,
    this.highlight = false,
    this.compact = false,
  });

  final GameItem? item;
  final int? level;
  final VoidCallback? onTap;
  final bool selected;
  final bool available;
  final bool showLevel;
  final String? emptyLabel;
  final bool highlight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final stamp = item;
    final hasStamp = stamp != null;
    final effectiveLevel = (level ?? stamp?.level ?? 1).clamp(
      1,
      GameItem.maxStampLevel,
    );
    final emptyText = emptyLabel ?? '';
    final borderColor = highlight
        ? GameThemeColors.cyan
        : Colors.white.withValues(alpha: hasStamp ? 0.22 : 0.10);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.all(compact ? 5 : 7),
          decoration: BoxDecoration(
            color: hasStamp
                ? const Color(0xFF0E1A2B).withValues(alpha: 0.94)
                : Colors.black.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: highlight ? 2 : 1.2,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: GameThemeColors.cyan.withValues(alpha: 0.22),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: hasStamp
                      ? Opacity(
                          opacity: available ? 1 : 0.35,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: StampWidget(
                              item: stamp,
                              level: effectiveLevel,
                            ),
                          ),
                        )
                      : emptyText.isEmpty
                          ? const SizedBox.shrink()
                          : Text(
                              emptyText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.34),
                                fontSize: compact ? 10 : 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                ),
              ),
              if (!available && hasStamp)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Icon(
                    Icons.lock,
                    size: compact ? 13 : 15,
                    color: Colors.white54,
                  ),
                ),
              if (showLevel && hasStamp)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: compact ? 20 : 22,
                    ),
                    height: compact ? 18 : 20,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: GameThemeColors.cyan.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      '$effectiveLevel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
