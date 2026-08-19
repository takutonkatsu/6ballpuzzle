import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../audio/sfx.dart';
import '../data/models/badge_item.dart';
import '../data/models/game_item.dart';
import '../friends/friend_manager.dart';
import '../network/ranking_manager.dart';
import 'components/game_pressable.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/player_icon_image.dart';
import 'components/season_rank_badge_icon.dart';
import 'profile_screen.dart';
import 'theme/game_theme_colors.dart';

class FriendScreen extends StatefulWidget {
  const FriendScreen({
    super.key,
    required this.onFriendBattle,
    this.embedded = false,
    this.refreshToken = 0,
  });

  final Future<void> Function(FriendEntry friend) onFriendBattle;
  final bool embedded;
  final int refreshToken;

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen> {
  late Future<List<FriendEntry>> _friendsFuture;
  bool _isBusy = false;
  String? _generatedUrl;

  @override
  void initState() {
    super.initState();
    _friendsFuture = FriendManager.instance.fetchFriends();
  }

  @override
  void didUpdateWidget(covariant FriendScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) {
      _friendsFuture = FriendManager.instance.fetchFriends();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _friendsFuture = FriendManager.instance.fetchFriends();
    });
  }

  Future<String> _createOrGetLink() async {
    if (_generatedUrl != null && _generatedUrl!.isNotEmpty) {
      return _generatedUrl!;
    }
    final code = await FriendManager.instance.createFriendCode();
    final url = FriendManager.instance.friendUrlForCode(code);
    if (mounted) {
      setState(() {
        _generatedUrl = url;
      });
    } else {
      _generatedUrl = url;
    }
    return url;
  }

  Future<String> _createQrAppLink() async {
    return _createOrGetLink();
  }

  Future<void> _shareLink() async {
    if (_isBusy) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      final url = await _createOrGetLink();
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: 'リンクをクリックして、ヘキサゴンのフレンドになりましょう！\n$url',
          subject: 'ヘキサゴン フレンド追加',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showSnack('リンク共有に失敗しました: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _showQrCode() async {
    if (_isBusy) {
      return;
    }
    setState(() => _isBusy = true);
    try {
      final url = await _createQrAppLink();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: GameThemeColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: GameThemeColors.cyan.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'フレンドを追加',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'QRコードを読み取ると、相手のフレンド一覧にすぐ登録されます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      AppSfx.playUiTap();
                      Navigator.of(dialogContext).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.withValues(alpha: 0.88),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '閉じる',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showSnack('QRコードを表示できませんでした: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: !widget.embedded,
      child: Column(
        children: [
          if (widget.embedded) _buildEmbeddedHeader(),
          Expanded(child: _buildFriendList()),
        ],
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return Scaffold(
      backgroundColor: GameThemeColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'フレンド',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: content,
    );
  }

  Widget _buildEmbeddedHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FRIEND',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: GameThemeColors.cyan,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
          Text(
            'フレンド',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendList() {
    return FutureBuilder<List<FriendEntry>>(
      future: _friendsFuture,
      builder: (context, snapshot) {
        final friends = snapshot.data ?? const <FriendEntry>[];
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: GameThemeColors.cyan,
                onRefresh: _reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Text(
                            'フレンドを読み込み中...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else if (friends.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Text(
                            'まだフレンドはいません。',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final friend in friends) ...[
                        _buildFriendRow(friend),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _buildAddPanel(friends.length),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddPanel(int friendCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GameThemeColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameThemeColors.cyan.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _wideButton('リンク共有', _shareLink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _wideButton('QRコード表示', _showQrCode),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'フレンド数 $friendCount/${FriendManager.maxFriends}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendRow(FriendEntry friend) {
    final bannerColor = _bannerColor(friend.profileBannerId);
    return GamePressable(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        AppSfx.playUiTap();
        _showFriendActions(friend);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.lerp(bannerColor, Colors.black, 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: bannerColor.withValues(alpha: 0.42)),
        ),
        child: Row(
          children: [
            _avatar(friend),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        flex: 10,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            friend.displayName,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 13,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _onlineDot(friend),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _badgeRow(friend.equippedBadgeIds),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const HexagonTrophyIcon(size: 18),
                const SizedBox(width: 4),
                Text(
                  '${friend.rating}',
                  style: const TextStyle(
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _onlineDot(FriendEntry friend) {
    final color = _presenceColor(friend);
    final label = _presenceLabel(friend);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _presenceLabel(FriendEntry friend) {
    if (!friend.online) {
      return 'オフライン';
    }
    if (!friend.inBattle) {
      return 'オンライン';
    }
    return switch (friend.activityMode) {
      'ranked' => 'ランク戦 プレイ中',
      'endless' => 'エンドレス プレイ中',
      'daily' => 'デイリー プレイ中',
      'computer' => 'コンピュータ対戦 プレイ中',
      'friend' => 'フレンド対戦 プレイ中',
      'arena' => 'アリーナ プレイ中',
      'tutorial' => '練習中',
      _ => 'プレイ中',
    };
  }

  Color _presenceColor(FriendEntry friend) {
    if (!friend.online) {
      return Colors.white30;
    }
    if (!friend.inBattle) {
      return Colors.lightGreenAccent;
    }
    return switch (friend.activityMode) {
      'ranked' => GameThemeColors.ranked,
      'endless' => GameThemeColors.endless,
      'daily' => GameThemeColors.blueSide,
      'computer' => GameThemeColors.computer,
      'friend' => GameThemeColors.friend,
      'arena' => GameThemeColors.arena,
      'tutorial' => GameThemeColors.cyan,
      _ => Colors.orangeAccent,
    };
  }

  Widget _avatar(FriendEntry friend) {
    final frameColor = _frameColor(friend.playerIconFrameId);
    final icon = PlayerIconImage(
      iconId: friend.playerIconId,
      fallbackIcon: Icons.person,
      size: 25,
    );
    if (GameItemCatalog.byId(friend.playerIconFrameId)?.colorName ==
        'rainbow') {
      return RainbowFrameRing(
        size: 50,
        strokeWidth: 4,
        child: icon,
      );
    }
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: frameColor.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: frameColor, width: 2),
      ),
      child: Center(child: icon),
    );
  }

  Widget _badgeRow(List<String> badgeIds) {
    final shown = badgeIds.take(3).toList();
    if (shown.isEmpty) {
      return const SizedBox(height: 22);
    }
    return Row(
      children: [
        for (final id in shown) ...[
          _badgeIcon(id),
          const SizedBox(width: 5),
        ],
      ],
    );
  }

  Widget _badgeIcon(String id) {
    final seasonBadge = SeasonRankBadge.fromId(id);
    if (seasonBadge != null) {
      return SizedBox(
        width: 24,
        height: 24,
        child: SeasonRankBadgeIcon(
          rank: seasonBadge.rank,
          kind: seasonBadge.kind,
        ),
      );
    }
    final badge = BadgeCatalog.findById(id);
    return Icon(
      badge?.icon ?? Icons.workspace_premium,
      color: badge?.frameColor ?? GameThemeColors.cyan,
      size: 22,
    );
  }

  Future<void> _showFriendActions(FriendEntry friend) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: GameThemeColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  friend.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                _wideButton('プロフィールを表示', () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        playerUid: friend.uid,
                        initialEntry: RankingEntry(
                          uid: friend.uid,
                          displayName: friend.displayName,
                          rating: friend.rating,
                          publicId: friend.publicId,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
                _wideButton(
                  'フレンド対戦',
                  () {
                    Navigator.of(sheetContext).pop();
                    if (!widget.embedded) {
                      Navigator.of(context).pop();
                    }
                    unawaited(widget.onFriendBattle(friend));
                  },
                  color: GameThemeColors.friend,
                ),
                const SizedBox(height: 10),
                _wideButton(
                  '削除',
                  () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_confirmDelete(friend));
                  },
                  color: Colors.redAccent,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(FriendEntry friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            color: GameThemeColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.68),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'フレンドを削除しますか？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${friend.displayName}さんをフレンドから削除します。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _dialogButton(
                      'キャンセル',
                      GameThemeColors.cyan,
                      () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _dialogButton(
                      '削除',
                      Colors.redAccent,
                      () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    await FriendManager.instance.deleteFriend(friend.uid);
    if (mounted) {
      await _reload();
      _showSnack('フレンドを削除しました。');
    }
  }

  Widget _wideButton(
    String label,
    FutureOr<void> Function() onTap, {
    Color color = GameThemeColors.cyan,
  }) {
    return SizedBox(height: 46, child: _button(label, onTap, color: color));
  }

  Widget _button(
    String label,
    FutureOr<void> Function() onTap, {
    Color color = GameThemeColors.cyan,
  }) {
    return GamePressable(
      enabled: !_isBusy,
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        AppSfx.playUiTap();
        unawaited(Future<void>.sync(onTap));
      },
      child: Opacity(
        opacity: _isBusy ? 0.54 : 1,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.34),
                color.withValues(alpha: 0.14),
                Colors.black.withValues(alpha: 0.30),
              ],
            ),
            border:
                Border.all(color: color.withValues(alpha: 0.86), width: 1.6),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      height: 44,
      child: GamePressable(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AppSfx.playUiTap();
          onPressed();
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: color.withValues(alpha: 0.82), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _frameColor(String frameId) {
    final frame = GameItemCatalog.byId(frameId);
    return switch (frame?.colorName) {
      'red' => GameThemeColors.friend,
      'orange' => Colors.orangeAccent,
      'yellow' => GameThemeColors.computer,
      'lime' => Colors.limeAccent,
      'green' => GameThemeColors.endless,
      'blue' => GameThemeColors.blueSide,
      'purple' => Colors.purpleAccent,
      'white' => Colors.white,
      'black' => const Color(0xFF05070D),
      'rainbow' => const Color(0xFFFFD54A),
      _ => GameThemeColors.cyan,
    };
  }

  Color _bannerColor(String bannerId) {
    final banner = GameItemCatalog.byId(bannerId);
    return switch (banner?.colorName) {
      'red' => Colors.redAccent,
      'orange' => Colors.orangeAccent,
      'yellow' => GameThemeColors.computer,
      'lime' => Colors.limeAccent,
      'green' => GameThemeColors.endless,
      'blue' => GameThemeColors.blueSide,
      'purple' => Colors.purpleAccent,
      'white' => Colors.white70,
      'black' => const Color(0xFF05070D),
      _ => GameThemeColors.cyan,
    };
  }
}
