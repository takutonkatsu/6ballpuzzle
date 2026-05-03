import 'package:flutter/material.dart';

class HexagonCoinIcon extends StatelessWidget {
  const HexagonCoinIcon({
    super.key,
    this.size = 18,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Hexagon_Coin.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class HexagonTrophyIcon extends StatelessWidget {
  const HexagonTrophyIcon({
    super.key,
    this.size = 18,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Hexagon_Trophy.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class HexagonCoinAmount extends StatelessWidget {
  const HexagonCoinAmount(
    this.amount, {
    super.key,
    this.color = Colors.amberAccent,
    this.iconSize = 16,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w900,
    this.mainAxisSize = MainAxisSize.min,
    this.prefix = '',
  });

  final int amount;
  final Color color;
  final double iconSize;
  final double fontSize;
  final FontWeight fontWeight;
  final MainAxisSize mainAxisSize;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: mainAxisSize,
      children: [
        HexagonCoinIcon(size: iconSize),
        const SizedBox(width: 4),
        Text(
          '$prefix$amount',
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
      ],
    );
  }
}

class HexagonTrophyAmount extends StatelessWidget {
  const HexagonTrophyAmount(
    this.amount, {
    super.key,
    this.color = Colors.amberAccent,
    this.iconSize = 16,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w900,
    this.prefix = '',
    this.suffix = '',
  });

  final int amount;
  final Color color;
  final double iconSize;
  final double fontSize;
  final FontWeight fontWeight;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HexagonTrophyIcon(size: iconSize),
        const SizedBox(width: 4),
        Text(
          '$prefix$amount$suffix',
          maxLines: 1,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
          ),
        ),
      ],
    );
  }
}
