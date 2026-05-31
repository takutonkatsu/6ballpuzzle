import 'package:flutter/material.dart';

class SeasonRankBadgeIcon extends StatelessWidget {
  const SeasonRankBadgeIcon({
    super.key,
    required this.rank,
    this.size = 32,
    this.dimmed = false,
  });

  final int rank;
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
              'assets/images/Badge/Badge_Ranking-removebg.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: size * 0.15,
            right: size * 0.15,
            bottom: size * 0.09,
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
