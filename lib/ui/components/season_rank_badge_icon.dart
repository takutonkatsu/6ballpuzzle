import 'package:flutter/material.dart';

import '../../data/models/badge_item.dart';

class SeasonRankBadgeIcon extends StatelessWidget {
  const SeasonRankBadgeIcon({
    super.key,
    required this.rank,
    this.kind = SeasonRankBadgeKind.ranked,
    this.size = 32,
    this.dimmed = false,
  });

  final int rank;
  final SeasonRankBadgeKind kind;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final textSize = (size * 0.23).clamp(7.0, 14.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: dimmed ? 0.35 : 1.0,
            child: Image.asset(
              kind == SeasonRankBadgeKind.endless
                  ? 'assets/images/Badge/Ranking_Badge_Endless.png'
                  : 'assets/images/Badge/Ranking_Badge_Rank.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: size * 0.12,
            right: size * 0.12,
            bottom: size * 0.07,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.06,
                vertical: size * 0.015,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: dimmed ? 0.22 : 0.48),
                borderRadius: BorderRadius.circular(size * 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: dimmed ? 0.18 : 0.34),
                  width: (size * 0.018).clamp(0.6, 1.1),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '#$rank',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: textSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
