enum BallColor {
  blue, green, red, yellow, purple
}

enum WazaType {
  none(1.0),
  straight(2.5),
  pyramid(4.0),
  hexagon(8.0);

  final double multiplier;
  const WazaType(this.multiplier);
}

enum CPUDifficulty { easy, normal, hard, oni }

enum OjamaType {
  straightSet,
  colorSet, // Pyramid/Hexagon set
}

class OjamaTask {
  final OjamaType type;
  final BallColor? startColor; 
  OjamaTask(this.type, {this.startColor});
}

class MoveOption {
  final double x;
  final int rot;
  final double score;
  MoveOption(this.x, this.rot, this.score);
}

class HexCoordinate {
  final int col;
  final int row;

  const HexCoordinate(this.col, this.row);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HexCoordinate && col == other.col && row == other.row;

  @override
  int get hashCode => col.hashCode ^ row.hashCode;

  @override
  String toString() => 'Hex($col, $row)';
}

class MatchResult {
  final Set<HexCoordinate> targets;
  final WazaType highestWaza;
  final List<List<HexCoordinate>> wazaPattern; 
  final BallColor? wazaColor;
  MatchResult(this.targets, this.highestWaza, {this.wazaPattern = const [], this.wazaColor});
}
