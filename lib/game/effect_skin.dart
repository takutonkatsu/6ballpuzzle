import 'package:flutter/material.dart';

enum EffectSkinKind { formation, ojama }

class EffectSkin {
  const EffectSkin({
    required this.id,
    required this.name,
    required this.kind,
    required this.color,
    required this.description,
  });

  final String id;
  final String name;
  final EffectSkinKind kind;
  final Color color;
  final String description;
}

class EffectSkinCatalog {
  EffectSkinCatalog._();

  static const String defaultFormationId = 'effect_formation_default';
  static const String defaultOjamaId = 'effect_ojama_default';

  static const List<EffectSkin> formationEffects = [
    EffectSkin(
      id: defaultFormationId,
      name: 'スタンダード',
      kind: EffectSkinKind.formation,
      color: Color(0xFF42E8FF),
      description: '軽い光輪とスパークでフォーメーション成立を強調します。',
    ),
    EffectSkin(
      id: 'effect_formation_burst',
      name: 'バースト',
      kind: EffectSkinKind.formation,
      color: Color(0xFFFFD84D),
      description: '成立地点から短い光条が走る派手めの演出です。',
    ),
    EffectSkin(
      id: 'effect_formation_arc',
      name: 'アーク',
      kind: EffectSkinKind.formation,
      color: Color(0xFF9B7CFF),
      description: '紫の弧が広がる、対戦向けの鋭い演出です。',
    ),
    EffectSkin(
      id: 'effect_formation_emerald',
      name: 'エメラルド',
      kind: EffectSkinKind.formation,
      color: Color(0xFF1EE6A8),
      description: '緑の粒子がまとまって弾ける軽量エフェクトです。',
    ),
  ];

  static const List<EffectSkin> ojamaEffects = [
    EffectSkin(
      id: defaultOjamaId,
      name: 'スタンダード',
      kind: EffectSkinKind.ojama,
      color: Color(0xFFFF5A6C),
      description: '妨害ボールに最低限の発光を追加します。',
    ),
    EffectSkin(
      id: 'effect_ojama_meteor',
      name: 'メテオ',
      kind: EffectSkinKind.ojama,
      color: Color(0xFFFF8A2A),
      description: '落下中に熱い残光をまとわせます。',
    ),
    EffectSkin(
      id: 'effect_ojama_crystal',
      name: 'クリスタル',
      kind: EffectSkinKind.ojama,
      color: Color(0xFF49E8FF),
      description: '透明感のある青い輝きをまとわせます。',
    ),
    EffectSkin(
      id: 'effect_ojama_thunder',
      name: 'サンダー',
      kind: EffectSkinKind.ojama,
      color: Color(0xFFFFE95C),
      description: '短い電撃ラインを走らせる演出です。',
    ),
  ];

  static const List<EffectSkin> all = [
    ...formationEffects,
    ...ojamaEffects,
  ];

  static EffectSkin byId(String id) {
    for (final skin in all) {
      if (skin.id == id) {
        return skin;
      }
    }
    if (id.startsWith('effect_ojama_')) {
      return ojamaEffects.first;
    }
    return formationEffects.first;
  }

  static bool isFormation(String id) =>
      byId(id).kind == EffectSkinKind.formation;

  static bool isOjama(String id) => byId(id).kind == EffectSkinKind.ojama;
}
