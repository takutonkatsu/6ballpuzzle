import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ranked_interstitial_debt_manager.dart';
import '../app_maintenance_manager.dart';
import '../app_settings.dart';
import '../app_notice_manager.dart';
import '../app_review_config.dart';
import '../audio/seamless_bgm.dart';
import '../audio/sfx.dart';
import '../data/player_data_manager.dart';
import '../game/arena_manager.dart';
import '../game/friend_match_limit_manager.dart';
import '../game/mission_catalog.dart';
import '../game/mission_manager.dart';
import '../invite/invite_manager.dart';
import '../data/models/game_item.dart';
import '../network/multiplayer_manager.dart';
import '../network/ranked_season_manager.dart';
import '../network/ranking_manager.dart';
import '../network/realtime_connection_guard.dart';
import '../network/server_time_manager.dart';
import '../purchases/ad_removal_purchase_manager.dart';
import '../game/game_models.dart';
import '../game/components/ball_component.dart';
import 'components/hexagon_grid_background.dart';
import 'components/hexagon_currency_icons.dart';
import 'components/interstitial_ad_manager.dart';
import 'components/rewarded_ad_manager.dart';
import 'components/screen_bottom_banner_ad.dart';
import 'components/stamp_widget.dart';
import 'collection_screen.dart';
import 'game_screen.dart';
import 'mission_screen.dart';
import 'profile_screen.dart';
import 'ranking_screen.dart';
import 'record_screen.dart';
import 'shop_screen.dart';
import 'theme/game_theme_colors.dart';

class HomeBootstrapData {
  const HomeBootstrapData({
    required this.playerName,
    required this.rating,
    this.pendingLevelUpRewardLog,
    this.pendingRankedSeasonResultLog,
    this.pendingAdminGrantLogs = const [],
    this.abandonedMatchMessage,
  });

  final String playerName;
  final int rating;
  final String? pendingLevelUpRewardLog;
  final String? pendingRankedSeasonResultLog;
  final List<String> pendingAdminGrantLogs;
  final String? abandonedMatchMessage;
}

class _SeasonResultViewData {
  const _SeasonResultViewData({
    required this.seasonName,
    required this.rating,
    required this.rank,
    required this.record,
    required this.winRate,
  });

  final String seasonName;
  final String rating;
  final String rank;
  final String record;
  final String winRate;

  factory _SeasonResultViewData.fromLog(String log) {
    final lines = log
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    String valueAfter(String prefix, String fallback) {
      final line = lines.cast<String?>().firstWhere(
            (line) => line?.startsWith(prefix) ?? false,
            orElse: () => null,
          );
      if (line == null) {
        return fallback;
      }
      return line.substring(prefix.length).trim();
    }

    return _SeasonResultViewData(
      seasonName: lines.isEmpty ? '前シーズン 結果' : lines.first,
      rating: valueAfter('最終レート:', '-'),
      rank: valueAfter('最終順位:', '圏外'),
      record: valueAfter('勝敗:', '-'),
      winRate: valueAfter('勝率:', '-'),
    );
  }
}

const Duration _homeBootstrapOnlineTimeout = Duration(seconds: 4);
const Color _homeCyan = GameThemeColors.cyan;
const Color _homeCyanBorder = GameThemeColors.cyanBorder;
const Color _rankedPurple = GameThemeColors.ranked;
const Color _rankedPurpleText = GameThemeColors.rankedText;
const Color _endlessGreen = GameThemeColors.endless;
const Color _computerYellow = GameThemeColors.computer;
const Color _friendPink = GameThemeColors.friend;
const Color _mutedButtonGrey = GameThemeColors.mutedButton;
const int _interstitialSkipTicketCost = 50000;
const Duration _interstitialSkipTicketDuration = Duration(minutes: 30);

Future<HomeBootstrapData> prepareHomeBootstrapData() async {
  final multiplayerManager = MultiplayerManager();
  final rankingManager = RankingManager.instance;
  final playerDataManager = PlayerDataManager.instance;
  final arenaManager = ArenaManager.instance;
  final missionManager = MissionManager.instance;
  var savedName = '';

  try {
    await playerDataManager.load();
    savedName = await _readSavedPlayerNameForBootstrap();
    if (savedName.trim().isEmpty) {
      savedName = playerDataManager.displayPlayerName;
    }
    var rating = playerDataManager.currentRating;
    multiplayerManager.currentRating = rating;
    if (savedName.trim().isNotEmpty) {
      multiplayerManager.setPlayerName(savedName);
      await _withHomeBootstrapTimeout(
        playerDataManager.setPlayerName(savedName),
        label: 'player profile bootstrap',
      );
    }
    try {
      await _withHomeBootstrapTimeout(
        multiplayerManager.initializeUser(name: savedName),
        label: 'user bootstrap',
      );
      rating = playerDataManager.currentRating;
      multiplayerManager.currentRating = rating;
    } catch (_) {
      rating = playerDataManager.currentRating;
      multiplayerManager.currentRating = rating;
    }
    try {
      await _withHomeBootstrapTimeout(
        rankingManager.syncSeasonStateForCurrentPlayer(),
        label: 'season bootstrap',
      );
      await _withHomeBootstrapTimeout(
        playerDataManager.load(),
        label: 'season profile reload',
      );
      rating = playerDataManager.currentRating;
      multiplayerManager.currentRating = rating;
      await _withHomeBootstrapTimeout(
        rankingManager.updateMyRating(rating: rating),
        label: 'ranking bootstrap',
      );
    } catch (_) {
      // シーズン/ランキング同期の失敗でホーム起動を止めない。
    }

    await _loadHomeEconomyForBootstrap(
      playerDataManager: playerDataManager,
      missionManager: missionManager,
      arenaManager: arenaManager,
    );

    String? abandonedMatchMessage;
    final resolution = await _withHomeBootstrapTimeout(
      multiplayerManager.inspectSavedSession(),
      label: 'saved session bootstrap',
    );
    if (resolution != null) {
      if (resolution.newRating != null) {
        rating = resolution.newRating!;
        multiplayerManager.currentRating = rating;
        await _withHomeBootstrapTimeout(
          playerDataManager.setCurrentRating(rating),
          label: 'resolved rating bootstrap',
        );
        await _withHomeBootstrapTimeout(
          rankingManager.updateMyRating(rating: rating),
          label: 'resolved ranking bootstrap',
        );
      }

      final arenaTransition = await _applyResolvedOnlineSessionForBootstrap(
        resolution,
        playerDataManager: playerDataManager,
        arenaManager: arenaManager,
      );
      await multiplayerManager.clearSavedSession();
      await _loadHomeEconomyForBootstrap(
        playerDataManager: playerDataManager,
        missionManager: missionManager,
        arenaManager: arenaManager,
      );
      if (resolution.wasAbandoned) {
        abandonedMatchMessage = _buildAbandonedMatchMessageForBootstrap(
          resolution,
          arenaTransition: arenaTransition,
        );
      }
    }

    final pendingLevelUpRewardLog =
        await playerDataManager.consumePendingLevelUpRewardLog();
    await playerDataManager.consumePendingLoginBonusLog();
    final pendingAdminGrantLogs =
        await playerDataManager.consumePendingAdminGrantLogs();
    final pendingRankedSeasonResultLog =
        await playerDataManager.consumePendingRankedSeasonResultLog();

    return HomeBootstrapData(
      playerName: savedName,
      rating: rating,
      pendingLevelUpRewardLog: pendingLevelUpRewardLog,
      pendingRankedSeasonResultLog: pendingRankedSeasonResultLog,
      pendingAdminGrantLogs: pendingAdminGrantLogs,
      abandonedMatchMessage: abandonedMatchMessage,
    );
  } catch (_) {
    return HomeBootstrapData(
      playerName: savedName,
      rating: multiplayerManager.currentRating,
    );
  }
}

Future<T> _withHomeBootstrapTimeout<T>(
  Future<T> future, {
  required String label,
}) {
  return future.timeout(
    _homeBootstrapOnlineTimeout,
    onTimeout: () {
      throw TimeoutException(label, _homeBootstrapOnlineTimeout);
    },
  );
}

Future<void> _loadHomeEconomyForBootstrap({
  required PlayerDataManager playerDataManager,
  required MissionManager missionManager,
  required ArenaManager arenaManager,
}) async {
  await playerDataManager.load();
  await playerDataManager.checkDailyReset();
  await missionManager.load();
  await arenaManager.load();
}

Future<String> _readSavedPlayerNameForBootstrap() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString(_HomeScreenState._playerNameKey) ?? '';
    if (savedName.trim().isNotEmpty) {
      return savedName;
    }
    await PlayerDataManager.instance.load();
    return PlayerDataManager.instance.displayPlayerName;
  } on MissingPluginException {
    return PlayerDataManager.instance.displayPlayerName;
  }
}

Future<_ArenaRecordTransition?> _applyResolvedOnlineSessionForBootstrap(
  SavedSessionResolution resolution, {
  required PlayerDataManager playerDataManager,
  required ArenaManager arenaManager,
}) async {
  final isWin = resolution.isWin;
  if (isWin == null) {
    return null;
  }

  final mode = resolution.session.isArenaMode
      ? 'ARENA'
      : resolution.session.isRankedMode
          ? 'RANKED'
          : 'FRIEND';
  await playerDataManager.recordMatchResult(
    isWin: isWin,
    mode: mode,
    opponentName: resolution.opponentName ?? 'UNKNOWN',
    wazaCounts: const {
      'straight': 0,
      'pyramid': 0,
      'hexagon': 0,
    },
    isForfeitWin: isWin,
    ratingAfter: resolution.newRating,
    ratingDelta: resolution.ratingDelta,
  );
  if (!resolution.session.isArenaMode) {
    return null;
  }
  await arenaManager.load();
  final beforeWins = arenaManager.currentWins;
  final beforeLosses = arenaManager.currentLosses;
  final result = await arenaManager.recordArenaMatch(isWin);
  return _ArenaRecordTransition(
    beforeWins: beforeWins,
    beforeLosses: beforeLosses,
    afterWins: result.wins,
    afterLosses: result.losses,
  );
}

String _buildAbandonedMatchMessageForBootstrap(
  SavedSessionResolution resolution, {
  _ArenaRecordTransition? arenaTransition,
}) {
  final session = resolution.session;
  final modeLabel = session.isArenaMode
      ? 'アリーナ'
      : session.isRankedMode
          ? 'ランク戦'
          : 'フレンド対戦';
  final buffer = StringBuffer(
    resolution.wasOfflineDisconnect
        ? '前回$modeLabel中にデータ通信に接続できなかったため不戦敗となりました。'
        : '前回$modeLabel中にアプリを終了したため試合放棄となりました。',
  );
  final oldRating = resolution.oldRating;
  final newRating = resolution.newRating;
  if (session.isRankedMode &&
      !session.isArenaMode &&
      oldRating != null &&
      newRating != null) {
    buffer.write('\nレート：$oldRating→$newRating');
  }
  if (session.isArenaMode && arenaTransition != null) {
    buffer.write(
      '\nアリーナ：${arenaTransition.beforeWins}勝${arenaTransition.beforeLosses}敗'
      '→${arenaTransition.afterWins}勝${arenaTransition.afterLosses}敗',
    );
  }
  return buffer.toString();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.bootstrapData,
  });

  final HomeBootstrapData? bootstrapData;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ArenaRecordTransition {
  const _ArenaRecordTransition({
    required this.beforeWins,
    required this.beforeLosses,
    required this.afterWins,
    required this.afterLosses,
  });

  final int beforeWins;
  final int beforeLosses;
  final int afterWins;
  final int afterLosses;
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Object _bgmOwner = 'home_screen';

  static const _playerNameKey = 'player_name';
  static const _lastSeenNoticeIdKey = 'home_last_seen_notice_id';
  static const _shareFeatureNoticeHiddenDateKey =
      'home_share_feature_notice_hidden_date';
  static const _lastAdRemovalPromptAtKey = 'home_last_ad_removal_prompt_at';
  static const Duration _nameRegistrationSyncTimeout = Duration(seconds: 4);
  static const Duration _homeBgmDuration = Duration(microseconds: 96003651);
  static const Duration _adRemovalPromptCooldown = Duration(hours: 24);
  static const int _adRemovalPromptMinMatches = 3;
  static const bool _debugControlsEnabled = AppReviewConfig.debugMenuEnabled;
  static const bool _adGiftCodeIssuerEnabled =
      AppReviewConfig.adRemovalGiftCodeIssuerEnabled;
  final MultiplayerManager _multiplayerManager = MultiplayerManager();
  final RankingManager _rankingManager = RankingManager.instance;
  final PlayerDataManager _playerDataManager = PlayerDataManager.instance;
  final ArenaManager _arenaManager = ArenaManager.instance;
  final MissionManager _missionManager = MissionManager.instance;
  final TextEditingController _playerNameController = TextEditingController();
  late final List<BallColor> _rotatingBallColors = _randomRotatingBallColors();
  bool _isBusy = false;
  int _rating = MultiplayerManager.initialRating;
  int _level = 1;
  int _currentLevelExp = 0;
  int _nextLevelRequiredExp = 1000;
  int _coins = PlayerDataManager.initialCoins;
  int _claimableMissionCount = 0;
  int _completedMissionCount = 0;
  bool _hasUnseenCollectionItems = false;
  int _todayRankedWins = 0;
  String _currentSeasonName = 'シーズン--';
  String _seasonRankLabel = '圏外';
  String _dailyWinRankLabel = '圏外';
  bool _isLoadingProfile = true;
  bool _isLoadingNotice = false;
  int _unreadNoticeCount = 0;
  late AnimationController _animController;
  bool _isHomeBgmPlaying = false;
  bool _homeBgmSuspendedByLifecycle = false;
  bool _isInitialNamePromptVisible = false;
  bool _isOpeningProfileScreen = false;
  bool _isAdRemovalPromptVisible = false;
  bool _didCheckAdRemovalPromptThisSession = false;
  Timer? _seasonStateTimer;
  bool _isSyncingRankedSeason = false;

  // ignore: unused_element
  bool get _isArenaComingSoon => true;

  bool get _showsSettingsAdRemovalActions =>
      Theme.of(context).platform != TargetPlatform.android &&
      !(Theme.of(context).platform == TargetPlatform.iOS &&
          AppReviewConfig.isProdFlavor);

  void _playUiTap() {
    AppSfx.playUiTap();
  }

  IconData _playerIconData(String iconId) {
    return switch (iconId) {
      'icon_bolt' => Icons.bolt,
      'icon_star' => Icons.star,
      'icon_gamepad' => Icons.sports_esports,
      'icon_sword' => Icons.gavel,
      'icon_hexagon' => Icons.hexagon,
      'icon_trophy' => Icons.emoji_events,
      'icon_medal' => Icons.military_tech,
      'icon_crown' => Icons.workspace_premium,
      'icon_diamond' => Icons.diamond,
      'icon_fire' => Icons.local_fire_department,
      'icon_water' => Icons.water_drop,
      'icon_moon' => Icons.dark_mode,
      'icon_visibility' => Icons.visibility,
      'icon_rocket' => Icons.rocket_launch,
      'icon_shield' => Icons.shield,
      'icon_terminal' => Icons.terminal,
      'icon_smile' => Icons.sentiment_satisfied_alt,
      'icon_ribbon' => Icons.workspace_premium,
      'icon_heart' => Icons.favorite,
      'icon_music' => Icons.music_note,
      'icon_cafe' => Icons.coffee,
      'icon_flower' => Icons.local_florist,
      'icon_bell' => Icons.notifications,
      'icon_skull' => Icons.dangerous,
      _ => Icons.person,
    };
  }

  Color _playerIconFrameColor(String frameId) {
    final frame = GameItemCatalog.byId(frameId);
    return switch (frame?.colorName) {
      'red' => _friendPink,
      'orange' => Colors.orangeAccent,
      'yellow' => _computerYellow,
      'lime' => Colors.limeAccent,
      'green' => _endlessGreen,
      'blue' => _homeCyan,
      'purple' => Colors.purpleAccent,
      'black' => Colors.white70,
      'rainbow' => const Color(0xFFFFD54A),
      _ => _homeCyan,
    };
  }

  Widget _buildCoinAmount(
    int amount, {
    Color color = const Color(0xFFEAF6FF),
    double iconSize = 12,
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w900,
    MainAxisSize mainAxisSize = MainAxisSize.min,
    String prefix = '',
  }) {
    return HexagonCoinAmount(
      amount,
      color: color,
      iconSize: iconSize,
      fontSize: fontSize,
      fontWeight: fontWeight,
      mainAxisSize: mainAxisSize,
      prefix: prefix,
    );
  }

  // ignore: unused_element
  Widget _buildArenaInfoLine({
    required String label,
    required int amount,
    required Alignment alignment,
    required Color color,
  }) {
    final textAlign = alignment.x > 0 ? TextAlign.right : TextAlign.left;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment:
            alignment.x > 0 ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: textAlign,
              style: TextStyle(
                color: color,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 4),
            _buildCoinAmount(
              amount,
              color: const Color(0xFFEAF6FF),
              iconSize: 11,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ],
        ),
      ),
    );
  }

  List<BallColor> _randomRotatingBallColors() {
    final random = math.Random();
    return List.generate(
      3,
      (_) => BallColor.values[random.nextInt(BallColor.values.length)],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.bootstrapData case final bootstrapData?) {
      _applyBootstrapData(bootstrapData);
    } else {
      _loadPlayerName();
      unawaited(_loadPlayerEconomy());
      unawaited(_maybeResumeSavedOnlineSession());
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    unawaited(_refreshCurrentSeasonName());
    unawaited(_loadRemoteNotice(showUnread: true));
    if (widget.bootstrapData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowShareFeatureNotice());
      });
    }
    _startSeasonStateMonitor();
    unawaited(RewardedAdManager.instance.warmUp());
    unawaited(_startHomeBgm());
  }

  @override
  void dispose() {
    unawaited(_stopHomeBgm());
    _seasonStateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _animController.dispose();
    _playerNameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeHomeBgmFromLifecycle());
      unawaited(_refreshCurrentSeasonName(forceRefresh: true));
      unawaited(_checkRankedSeasonBoundary(showResultLog: true));
      unawaited(_loadRemoteNotice(showUnread: true));
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_suspendHomeBgmForLifecycle());
    }
  }

  Future<void> _suspendHomeBgmForLifecycle() async {
    if (_homeBgmSuspendedByLifecycle) {
      return;
    }
    _homeBgmSuspendedByLifecycle = true;
    await SeamlessBgm.instance.suspendForExternalAudio();
  }

  Future<void> _resumeHomeBgmFromLifecycle() async {
    if (_homeBgmSuspendedByLifecycle) {
      _homeBgmSuspendedByLifecycle = false;
      await SeamlessBgm.instance.resumeFromExternalAudio();
    }
    await _startHomeBgm(forceRestart: !SeamlessBgm.instance.isPlaying);
  }

  void _startSeasonStateMonitor() {
    _seasonStateTimer?.cancel();
    _seasonStateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_checkRankedSeasonBoundary(showResultLog: true)),
    );
  }

  Future<void> _refreshCurrentSeasonName({bool forceRefresh = false}) async {
    try {
      final nowJst =
          await ServerTimeManager.instance.nowJst(forceRefresh: forceRefresh);
      final seasonId =
          RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentSeasonName = RankedSeasonManager.seasonName(seasonId);
      });
    } catch (_) {
      // サーバー時刻取得失敗時だけ一時表示のままにする。
    }
  }

  Future<void> _checkRankedSeasonBoundary({bool showResultLog = false}) async {
    if (_isSyncingRankedSeason) {
      return;
    }
    try {
      await _playerDataManager.load();
      final savedSeasonId = _playerDataManager.rankedSeasonId;
      final nowJst = await ServerTimeManager.instance.nowJst();
      final currentSeasonId =
          RankedSeasonManager.currentSeasonId(nowJstOverride: nowJst);
      if (mounted) {
        setState(() {
          _currentSeasonName = RankedSeasonManager.seasonName(currentSeasonId);
        });
      }
      if (savedSeasonId.isNotEmpty && savedSeasonId != currentSeasonId) {
        await _syncRankedSeasonState(showResultLog: showResultLog);
      }
    } catch (_) {
      // シーズン監視の失敗でホーム画面は止めない。
    }
  }

  Future<void> _startHomeBgm({bool forceRestart = false}) async {
    if (_isHomeBgmPlaying && SeamlessBgm.instance.isPlaying && !forceRestart) {
      return;
    }
    try {
      _isHomeBgmPlaying = true;
      await SeamlessBgm.instance.setMasterVolume(
        AppSettings.instance.musicVolume.value,
      );
      await SeamlessBgm.instance.play(
        assetPath: 'audio/home_screen_bgm01.wav',
        duration: _homeBgmDuration,
        volume: 0.576,
        owner: _bgmOwner,
        forceRestart: forceRestart,
      );
    } catch (_) {
      _isHomeBgmPlaying = false;
    }
  }

  Future<void> _stopHomeBgm() async {
    if (!_isHomeBgmPlaying && !SeamlessBgm.instance.isPlaying) {
      return;
    }
    _isHomeBgmPlaying = false;
    try {
      await SeamlessBgm.instance.stop(owner: _bgmOwner);
    } catch (_) {
      // BGM停止失敗で画面遷移や破棄を止めない。
    }
  }

  void _applyBootstrapData(HomeBootstrapData bootstrapData) {
    _playerNameController.text = bootstrapData.playerName;
    _multiplayerManager.setPlayerName(bootstrapData.playerName);
    _rating = bootstrapData.rating;
    _isLoadingProfile = false;
    _syncPlayerEconomyState();
    unawaited(_refreshPlayerEconomy());
    unawaited(_syncRankedSeasonState(showResultLog: true));
    unawaited(
      _syncPlayerProfileOnline(rating: bootstrapData.rating).catchError((_) {}),
    );

    final pendingLevelUpRewardLog = bootstrapData.pendingLevelUpRewardLog;
    if (pendingLevelUpRewardLog != null && pendingLevelUpRewardLog.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          _showAlert(
            context,
            'レベルアップ',
            pendingLevelUpRewardLog,
          ),
        );
      });
    }

    final pendingAdminGrantLogs = bootstrapData.pendingAdminGrantLogs;
    if (pendingAdminGrantLogs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_showPendingRewardLogs(pendingAdminGrantLogs));
      });
    }

    final pendingRankedSeasonResultLog =
        bootstrapData.pendingRankedSeasonResultLog;
    if (pendingRankedSeasonResultLog != null &&
        pendingRankedSeasonResultLog.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          _showAlert(
            context,
            'シーズン結果',
            pendingRankedSeasonResultLog,
          ),
        );
      });
    }

    final abandonedMatchMessage = bootstrapData.abandonedMatchMessage;
    if (abandonedMatchMessage != null && abandonedMatchMessage.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          _showAlert(
            context,
            '試合放棄',
            abandonedMatchMessage,
          ),
        );
      });
    }

    _scheduleInitialNameRegistrationIfNeeded();
  }

  Future<void> _loadPlayerEconomy() async {
    try {
      await _playerDataManager.load();
      await _playerDataManager.claimPendingServerGrants();
      await _playerDataManager.checkDailyReset();
      await _missionManager.load();
      await _arenaManager.load();
      final regularClaimableCount =
          await _missionManager.regularClaimableCount();
      final pendingLevelUpRewardLog =
          await _playerDataManager.consumePendingLevelUpRewardLog();
      final pendingAdminGrantLogs =
          await _playerDataManager.consumePendingAdminGrantLogs();
      await _playerDataManager.consumePendingLoginBonusLog();
      if (!mounted) {
        return;
      }
      setState(() {
        _syncPlayerEconomyState(regularClaimableCount: regularClaimableCount);
      });
      if (pendingLevelUpRewardLog != null &&
          pendingLevelUpRewardLog.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          unawaited(
            _showAlert(
              context,
              'レベルアップ',
              pendingLevelUpRewardLog,
            ),
          );
        });
      }
      if (pendingAdminGrantLogs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          unawaited(_showPendingRewardLogs(pendingAdminGrantLogs));
        });
      }
      unawaited(_maybeShowAdRemovalPrompt());
    } catch (_) {
      // ローカルデータ読込に失敗してもホーム表示は継続する。
    }
  }

  Future<void> _showPendingRewardLogs(List<String> logs) async {
    for (final log in logs) {
      if (!mounted) {
        return;
      }
      final lines = log
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final title = lines.isEmpty ? '報酬' : lines.first;
      final message = lines.length <= 1 ? log : lines.skip(1).join('\n');
      await _showAlert(
        context,
        title,
        message,
        buttonLabel: '受け取る',
      );
      await _refreshPlayerEconomy();
    }
  }

  Future<void> _refreshPlayerEconomy() async {
    await _playerDataManager.load();
    await _playerDataManager.claimPendingServerGrants();
    await _playerDataManager.checkDailyReset();
    await _missionManager.load();
    await _arenaManager.load();
    final regularClaimableCount = await _missionManager.regularClaimableCount();
    if (!mounted) {
      return;
    }
    setState(() {
      _syncPlayerEconomyState(regularClaimableCount: regularClaimableCount);
    });
    unawaited(_maybeShowAdRemovalPrompt());
  }

  Future<void> _maybeShowAdRemovalPrompt() async {
    if (_didCheckAdRemovalPromptThisSession || _isAdRemovalPromptVisible) {
      return;
    }
    _didCheckAdRemovalPromptThisSession = true;
    if (!mounted ||
        !AdRemovalPurchaseManager.isSupportedPlatform ||
        !AdRemovalPurchaseManager.instance.isConfigured ||
        AppSettings.instance.adsRemoved.value ||
        _playerDataManager.totalMatches < _adRemovalPromptMinMatches) {
      return;
    }
    final purchaseReady = await AdRemovalPurchaseManager.instance.initialize();
    if (!purchaseReady || AppSettings.instance.adsRemoved.value) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastPromptAtMillis = prefs.getInt(_lastAdRemovalPromptAtKey) ?? 0;
    final now = DateTime.now();
    if (lastPromptAtMillis > 0) {
      final lastPromptAt =
          DateTime.fromMillisecondsSinceEpoch(lastPromptAtMillis);
      if (now.difference(lastPromptAt) < _adRemovalPromptCooldown) {
        return;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted ||
        _isAdRemovalPromptVisible ||
        _isInitialNamePromptVisible ||
        AppSettings.instance.adsRemoved.value) {
      return;
    }
    _isAdRemovalPromptVisible = true;
    await prefs.setInt(_lastAdRemovalPromptAtKey, now.millisecondsSinceEpoch);
    try {
      await _showAdRemovalPromptDialog();
    } finally {
      _isAdRemovalPromptVisible = false;
    }
  }

  Future<void> _showAdRemovalPromptDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: 'もっと快適にプレイ',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '広告削除を有効にすると、広告なしで遊べるほか、毎日の無料ガチャや報酬アップが利用できます。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _buildAdRemovalBenefitLine('広告の完全削除'),
              _buildAdRemovalBenefitLine('毎日1回の無料ガチャ'),
              _buildAdRemovalBenefitLine('無制限のフレンド対戦'),
              _buildAdRemovalBenefitLine('対戦後のコイン報酬が毎回3倍に'),
              _buildAdRemovalBenefitLine('デイリーミッションのコイン獲得量が2倍に'),
              const SizedBox(height: 16),
              _buildCyberDialogButton(
                label: '広告削除を見る',
                accentColor: _homeCyan,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  unawaited(_showAdRemovalDialog(context));
                },
              ),
              const SizedBox(height: 10),
              _buildCyberDialogButton(
                label: 'あとで',
                accentColor: Colors.white54,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _syncPlayerEconomyState({int regularClaimableCount = 0}) {
    _level = _playerDataManager.level;
    _currentLevelExp = _playerDataManager.currentLevelExp;
    _nextLevelRequiredExp = _playerDataManager.nextLevelRequiredExp;
    _coins = _playerDataManager.coins;
    final allClearClaimableCount = (!AppSettings.instance.adsRemoved.value &&
            _missionManager.allMissionsComplete &&
            !_missionManager.isAllClearBonusClaimed)
        ? 1
        : 0;
    _claimableMissionCount = _missionManager.claimableCount +
        regularClaimableCount +
        allClearClaimableCount;
    _hasUnseenCollectionItems = _playerDataManager.hasUnseenCollectionItems;
    _completedMissionCount =
        _playerDataManager.currentMissions.where((mission) {
      final progress = (mission['progress'] as num?)?.toInt() ?? 0;
      final target = (mission['target'] as num?)?.toInt() ?? 0;
      return progress >= target;
    }).length;
  }

  Future<void> _refreshRankingSummary({bool forceRefresh = false}) async {
    try {
      final summary = await _rankingManager
          .fetchMySummary(
            forceRefresh: forceRefresh,
          )
          .timeout(_nameRegistrationSyncTimeout);
      if (!mounted) {
        return;
      }
      setState(() {
        _todayRankedWins = summary.dailyWins;
        _seasonRankLabel = summary.ratingRankLabel;
        _dailyWinRankLabel = summary.dailyWinRankLabel;
        if (_playerDataManager.rankedSeasonId.isNotEmpty) {
          _currentSeasonName = RankedSeasonManager.seasonName(
            _playerDataManager.rankedSeasonId,
          );
        }
      });
    } catch (_) {
      // ランキング取得失敗はホーム表示を止めない。
    }
  }

  Future<void> _loadRemoteNotice({
    bool showUnread = false,
    bool forceDialog = false,
  }) async {
    if (_isLoadingNotice && !forceDialog) {
      return;
    }
    _isLoadingNotice = true;
    try {
      final notices = await AppNoticeManager.fetchActiveNotices();
      if (!mounted) {
        return;
      }

      if (notices.isEmpty) {
        if (mounted) {
          setState(() {
            _unreadNoticeCount = 0;
          });
        }
        if (forceDialog) {
          await _showAlert(context, 'お知らせ', '現在のお知らせはありません。');
        }
        return;
      }

      if (forceDialog) {
        await _showNoticeList(notices);
        return;
      }

      if (!showUnread) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final seenIds = _seenNoticeIds(prefs);
      final unreadCount =
          notices.where((notice) => !seenIds.contains(notice.id)).length;
      setState(() {
        _unreadNoticeCount = unreadCount;
      });
    } finally {
      _isLoadingNotice = false;
    }
  }

  Future<void> _maybeShowShareFeatureNotice() async {
    if (!mounted) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _localDateKey(DateTime.now());
    if (prefs.getString(_shareFeatureNoticeHiddenDateKey) == todayKey) {
      return;
    }
    if (!mounted || _isInitialNamePromptVisible) {
      return;
    }
    await _showShareFeatureNoticeDialog(todayKey);
  }

  String _localDateKey(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  Future<void> _showShareFeatureNoticeDialog(String todayKey) {
    var hideToday = false;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> close() async {
              if (hideToday) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(
                  _shareFeatureNoticeHiddenDateKey,
                  todayKey,
                );
              }
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }

            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: '結果をシェア機能追加',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildShareNoticeMessage(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              hideToday = !hideToday;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Row(
                            children: [
                              Checkbox(
                                value: hideToday,
                                onChanged: (value) {
                                  setDialogState(() {
                                    hideToday = value ?? false;
                                  });
                                },
                                activeColor: _homeCyan,
                                checkColor: Colors.black,
                                side: const BorderSide(
                                  color: _homeCyanBorder,
                                  width: 1.4,
                                ),
                              ),
                              const Expanded(
                                child: Text(
                                  '今日はもう表示しない',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 118,
                        child: _buildCyberDialogButton(
                          label: '閉じる',
                          accentColor: _homeCyan,
                          onPressed: () => unawaited(close()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showNoticeList(List<AppNotice> notices) async {
    await _markNoticesSeen(notices);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        AppNotice? selectedNotice;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final notice = selectedNotice;
            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: notice == null ? 'お知らせ' : notice.title,
              child: notice == null
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: notices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = notices[index];
                          return InkWell(
                            onTap: () {
                              _playUiTap();
                              setDialogState(() {
                                selectedNotice = item;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _homeCyanBorder,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (item.publishedAtText.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 3),
                                            child: Text(
                                              item.publishedAtText,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: _homeCyan,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (notice.publishedAtText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              notice.publishedAtText,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Text(
                          notice.message,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: '一覧へ',
                                accentColor: _homeCyan,
                                onPressed: () {
                                  setDialogState(() {
                                    selectedNotice = null;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: '閉じる',
                                accentColor: _homeCyan,
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            );
          },
        );
      },
    );
  }

  Set<String> _seenNoticeIds(SharedPreferences prefs) {
    try {
      final seenList = prefs.getStringList(_lastSeenNoticeIdKey);
      if (seenList != null) {
        return seenList.toSet();
      }
    } catch (_) {
      // 旧バージョンでは文字列で保存していたため、型違いは下で救済する。
    }
    String? legacy;
    try {
      legacy = prefs.getString(_lastSeenNoticeIdKey);
    } catch (_) {
      legacy = null;
    }
    return legacy == null || legacy.isEmpty ? <String>{} : {legacy};
  }

  Future<void> _markNoticesSeen(List<AppNotice> notices) async {
    final prefs = await SharedPreferences.getInstance();
    final seenIds = _seenNoticeIds(prefs)..addAll(notices.map((n) => n.id));
    await prefs.setStringList(_lastSeenNoticeIdKey, seenIds.toList());
    if (mounted) {
      setState(() {
        _unreadNoticeCount = 0;
      });
    }
  }

  Future<void> _syncRankedSeasonState({bool showResultLog = false}) async {
    if (_isSyncingRankedSeason) {
      return;
    }
    _isSyncingRankedSeason = true;
    try {
      await _rankingManager
          .syncSeasonStateForCurrentPlayer()
          .timeout(_nameRegistrationSyncTimeout);
      await _playerDataManager.load();
      final seasonRating = _playerDataManager.currentRating;
      _multiplayerManager.currentRating = seasonRating;
      if (!mounted) {
        return;
      }
      setState(() {
        _rating = seasonRating;
        _currentSeasonName = RankedSeasonManager.seasonName(
          _playerDataManager.rankedSeasonId,
        );
      });
      if (showResultLog) {
        final log =
            await _playerDataManager.consumePendingRankedSeasonResultLog();
        if (log != null && log.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(_showAlert(context, 'シーズン結果', log));
          });
        }
      }
      try {
        await _rankingManager
            .updateMyRating(
              rating: seasonRating,
              displayName: _playerDataManager.displayPlayerName,
            )
            .timeout(_nameRegistrationSyncTimeout);
      } catch (_) {
        // 新シーズンのランキング行作成に失敗しても結果ログは表示する。
      }
      unawaited(_refreshRankingSummary(forceRefresh: true));
    } catch (_) {
      unawaited(_refreshRankingSummary(forceRefresh: true));
    } finally {
      _isSyncingRankedSeason = false;
    }
  }

  double get _levelProgress {
    if (_nextLevelRequiredExp <= 0) {
      return 0;
    }
    return (_currentLevelExp / _nextLevelRequiredExp).clamp(0.0, 1.0);
  }

  void _scheduleInitialNameRegistrationIfNeeded() {
    if (_isInitialNamePromptVisible ||
        _isLoadingProfile ||
        _playerNameController.text.trim().isNotEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _isInitialNamePromptVisible ||
          _isLoadingProfile ||
          _playerNameController.text.trim().isNotEmpty) {
        return;
      }
      unawaited(_showInitialNameRegistrationDialog());
    });
  }

  Future<void> _saveAndSyncPlayerName(String name) async {
    final trimmed = name.trim();
    await _playerDataManager.setPlayerName(trimmed);
    _multiplayerManager.setPlayerName(trimmed);
    _playerNameController.text = _playerDataManager.displayPlayerName;
    await _syncPlayerNameOnline();
    if (!mounted) {
      return;
    }
    setState(() {});
    unawaited(_refreshRankingSummary(forceRefresh: true));
  }

  Future<void> _syncPlayerNameOnline() async {
    await _syncPlayerProfileOnline(rating: _rating);
  }

  Future<void> _syncPlayerProfileOnline({int? rating}) async {
    final syncRating = rating ?? _playerDataManager.currentRating;
    await Future.wait<void>(
      [
        _runRequiredProfileSyncTask(
          () => _multiplayerManager
              .updateUserName(_playerDataManager.playerName)
              .timeout(_nameRegistrationSyncTimeout),
        ),
        _runRequiredProfileSyncTask(
          () => _rankingManager
              .updateMyRating(
                rating: syncRating,
                displayName: _playerDataManager.displayPlayerName,
              )
              .timeout(_nameRegistrationSyncTimeout),
        ),
        _runRequiredProfileSyncTask(
          () => _playerDataManager
              .syncRecordSummary(force: true, rethrowErrors: true)
              .timeout(_nameRegistrationSyncTimeout),
        ),
      ],
      eagerError: false,
    );
  }

  Future<void> _runRequiredProfileSyncTask(
    Future<void> Function() task,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await task();
        return;
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _showInitialNameRegistrationDialog() async {
    if (_isInitialNamePromptVisible) {
      return;
    }
    _isInitialNamePromptVisible = true;
    final controller = TextEditingController(text: _playerNameController.text);
    final inviteCodeController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isSubmitting = false;
          String? errorText;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                if (isSubmitting) {
                  return;
                }
                final nextName = controller.text.trim();
                if (nextName.isEmpty) {
                  setDialogState(() {
                    errorText = '名前を入力してください。';
                  });
                  return;
                }
                setDialogState(() {
                  isSubmitting = true;
                  errorText = null;
                });
                try {
                  final inviteCode = inviteCodeController.text.trim();
                  await _saveAndSyncPlayerName(nextName);
                  InviteRedeemResult? inviteResult;
                  if (inviteCode.isNotEmpty) {
                    inviteResult = await InviteManager.instance.redeemCode(
                      inviteCode,
                      inviteeName: nextName,
                      inviteePublicId: _playerDataManager.playerId,
                    );
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (inviteResult != null && mounted) {
                    await _showInviteRedeemResult(
                      this.context,
                      inviteResult,
                    );
                  }
                } catch (error) {
                  setDialogState(() {
                    errorText = '$error';
                    isSubmitting = false;
                  });
                }
              }

              return PopScope(
                canPop: false,
                child: _buildCyberDialog(
                  accentColor: _homeCyan,
                  title: '名前を登録',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '最初にプレイヤー名を登録しましょう。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        maxLength: 10,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(submit()),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'プレイヤー名',
                          counterStyle: const TextStyle(color: Colors.white38),
                          labelStyle: const TextStyle(color: Colors.white70),
                          errorText: errorText,
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: _homeCyanBorder),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: _homeCyanBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: inviteCodeController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => unawaited(submit()),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: '招待コード（任意）',
                          helperText: '友達からコードを受け取っている場合はこちら',
                          helperStyle: TextStyle(color: Colors.white38),
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: _homeCyanBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: _homeCyanBorder),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildCyberDialogButton(
                        label: isSubmitting ? '登録中...' : '登録',
                        accentColor: _homeCyan,
                        onPressed: () {
                          if (isSubmitting) {
                            return;
                          }
                          unawaited(submit());
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
      inviteCodeController.dispose();
      _isInitialNamePromptVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      bottomNavigationBar: const ScreenBottomBannerAd(
        reserveSpaceWhenHidden: true,
      ),
      body: Stack(
        children: [
          const HexagonGridBackground(
            color: _homeCyan,
            opacity: 0.035,
            hexRadius: 30,
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBanner1(),
                const SizedBox(height: 12),
                _buildTopBanner2(),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const ballHeight = 152.0;
                            const spacing = 8.0;
                            final modeHeight =
                                (constraints.maxHeight - ballHeight - spacing)
                                    .clamp(120.0, 280.0);

                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _build3DRotatingBall(),
                                const SizedBox(height: spacing),
                                _buildModeSelectionCutout(height: modeHeight),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                _buildInterstitialSkipTicketHomeButton(),
                _buildBottomBannerTop(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner1() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final edgePadding = compact ? 8.0 : 16.0;
        final gap = compact ? 6.0 : 12.0;
        final levelProgressWidth = compact ? 34.0 : 52.0;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: edgePadding,
            vertical: 8,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  _playUiTap();
                  unawaited(_showLevelDetailsDialog());
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    border: Border.all(
                      color: _homeCyanBorder,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Lv.$_level',
                          style: const TextStyle(
                            color: _homeCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 5 : 7),
                      Container(
                        width: levelProgressWidth,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _levelProgress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _homeCyan,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: _buildProfileButton(compact: compact),
                  ),
                ),
              ),
              SizedBox(width: gap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: compact ? 68 : 78,
                  maxWidth: compact ? 82 : 96,
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(
                        color: _homeCyanBorder,
                      ),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      HexagonCoinIcon(size: compact ? 14 : 16),
                      SizedBox(width: compact ? 3 : 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$_coins',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: const TextStyle(
                              color: Color(0xFFEAF6FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileButton({required bool compact}) {
    final displayName = _playerNameController.text.trim().isEmpty
        ? 'プレイヤー'
        : _playerNameController.text.trim();
    final frameId = _playerDataManager.equippedIconFrameId;
    final frameColor = _playerIconFrameColor(frameId);

    return InkWell(
      onTap: () {
        _playUiTap();
        unawaited(_openProfileScreen());
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: compact ? 34 : 36,
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
        decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _homeCyanBorder,
            )),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPlayerIconAvatar(
              iconId: _playerDataManager.equippedPlayerIconId,
              frameId: frameId,
              color: frameColor,
              size: compact ? 18 : 22,
              iconSize: compact ? 13 : 15,
            ),
            SizedBox(width: compact ? 5 : 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  displayName,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: compact ? 0.4 : 0.8,
                    fontSize: compact ? 13 : 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerIconAvatar({
    required String iconId,
    required String frameId,
    required Color color,
    required double size,
    required double iconSize,
  }) {
    final icon = Icon(
      _playerIconData(iconId),
      color: Colors.white,
      size: iconSize,
    );
    if (GameItemCatalog.byId(frameId)?.colorName == 'rainbow') {
      return Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Color(0xFFFF4D6D),
              Color(0xFFFFD54A),
              Color(0xFF35F0FF),
              Color(0xFFB91DFF),
              Color(0xFFFF4D6D),
            ],
          ),
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            shape: BoxShape.circle,
          ),
          child: Center(child: icon),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: 0.72),
        ),
      ),
      child: icon,
    );
  }

  Future<void> _openProfileScreen() async {
    if (_isOpeningProfileScreen) {
      return;
    }
    _isOpeningProfileScreen = true;
    try {
      await _playerDataManager.setCurrentRating(_rating);
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      final savedName = await _readSavedPlayerName();
      if (!mounted) {
        return;
      }
      setState(() {
        _playerNameController.text = savedName;
      });
      _multiplayerManager.setPlayerName(savedName);
      unawaited(_multiplayerManager.updateUserName(savedName));
      await _refreshPlayerEconomy();
      unawaited(
        _rankingManager.updateMyRating(
          rating: _rating,
          displayName: savedName,
        ),
      );
      unawaited(_refreshRankingSummary(forceRefresh: true));
    } finally {
      _isOpeningProfileScreen = false;
    }
  }

  void _openRecordScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RecordScreen()),
    );
  }

  Future<void> _openCollectionScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
    );
    await _playerDataManager.clearUnseenCollectionItems();
    await _refreshPlayerEconomy();
  }

  Widget _buildTopBanner2() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: _openRankingScreen,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _homeCyanBorder)),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentSeasonName,
                        style: const TextStyle(
                          color: _homeCyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HexagonTrophyIcon(size: 16),
                          const SizedBox(width: 5),
                          Text(
                            _isLoadingProfile ? '...' : '$_rating',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (!_isLoadingProfile) ...[
                            const SizedBox(width: 6),
                            Text(
                              _seasonRankLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '今日 $_todayRankedWins勝  $_dailyWinRankLabel',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _homeCyan,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                children: [
                  _buildRoundIcon(
                    Icons.notifications,
                    _homeCyan,
                    () => unawaited(_loadRemoteNotice(forceDialog: true)),
                    tooltip: 'お知らせ',
                    badgeCount: _unreadNoticeCount,
                  ),
                  const SizedBox(width: 6),
                  _buildRoundIcon(
                    Icons.question_mark,
                    _homeCyan,
                    () => unawaited(_showHowToDialog()),
                    tooltip: '遊び方',
                  ),
                  const SizedBox(width: 6),
                  _buildRoundIcon(
                    Icons.settings,
                    _homeCyan,
                    () => unawaited(_showSettingsDialog()),
                    tooltip: '設定',
                  ),
                  if (_debugControlsEnabled) ...[
                    const SizedBox(width: 6),
                    _buildRoundIcon(
                      Icons.bug_report,
                      _homeCyan,
                      () => unawaited(_showDebugMenu()),
                      tooltip: 'デバッグ',
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (AdRemovalPurchaseManager.isSupportedPlatform) ...[
                    const SizedBox(width: 6),
                    _buildRoundIcon(
                      Icons.block,
                      _homeCyan,
                      () => unawaited(_showAdRemovalDialog(context)),
                      tooltip: '広告削除',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundIcon(
    IconData icon,
    Color color,
    VoidCallback onTap, {
    required String tooltip,
    int badgeCount = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          _playUiTap();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: 45,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tooltip,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.82),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount > 0)
              Positioned(
                right: 0,
                top: -5,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openRankingScreen() {
    _playUiTap();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const RankingScreen(),
        ),
      ),
    );
  }

  Future<void> _showLevelDetailsDialog() async {
    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }

    final currentLevel = _playerDataManager.level;
    final currentLevelExp = _playerDataManager.currentLevelExp;
    final requiredExp = _playerDataManager.nextLevelRequiredExp;
    final remainingExp = _playerDataManager.remainingExpToNextLevel;
    final nextRewardCoins = (currentLevel + 1) * 500;
    final progress = requiredExp <= 0
        ? 0.0
        : (currentLevelExp / requiredExp).clamp(0.0, 1.0);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          title: 'レベルステータス',
          accentColor: _homeCyan,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFF101827),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _homeCyanBorder,
                    width: 1.4,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          '現在のレベル',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$currentLevel',
                          style: const TextStyle(
                            color: _homeCyan,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(color: _homeCyan),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'EXP  $currentLevelExp / $requiredExp',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'あと $remainingExp',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amberAccent.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '次のレベルアップ報酬',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _buildCoinAmount(
                            nextRewardCoins,
                            color: const Color(0xFFEAF6FF),
                            iconSize: 15,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildCyberDialogButton(
                label: '閉じる',
                accentColor: _homeCyan,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _build3DRotatingBall() {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final rotation = _animController.value * math.pi * 2;
        const baseSize = 76.0;
        const centerX = 100.0;
        const centerY = 76.0;
        final triRadius = baseSize / math.sqrt(3);
        final balls = [
          (color: _rotatingBallColors[0], x: 0.0, y: -triRadius),
          (color: _rotatingBallColors[1], x: -baseSize / 2, y: triRadius / 2),
          (color: _rotatingBallColors[2], x: baseSize / 2, y: triRadius / 2),
        ].map((ball) {
          final projectedX = ball.x * math.cos(rotation);
          final depth = -ball.x * math.sin(rotation);
          final scale = 0.92 + ((depth / (baseSize / 2)) + 1) * 0.06;
          final size = baseSize * scale;
          return (
            color: ball.color,
            depth: depth,
            left: centerX + projectedX - size / 2,
            top: centerY + ball.y - size / 2,
            size: size,
          );
        }).toList()
          ..sort((a, b) => a.depth.compareTo(b.depth));

        return SizedBox(
          width: 200,
          height: 152,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final ball in balls)
                Positioned(
                  left: ball.left,
                  top: ball.top,
                  child: MiniBallWidget(
                    ballColor: ball.color,
                    size: ball.size,
                    showOuterGlow: false,
                    ballSkinId: _playerDataManager.equippedBallSkinId,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSelectionCutout({double height = 280}) {
    return SizedBox(
      height: height,
      width: 320,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _buildGridButton('エンドレス', _endlessGreen,
                            () => _showEndlessStartDialog(context),
                            alignment: Alignment.topLeft)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildGridButton(
                            'フレンド',
                            _friendPink,
                            _isBusy
                                ? null
                                : () => _showFriendBattleDialog(context),
                            alignment: Alignment.topRight)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                        child: _buildGridButton(
                            'コンピュータ',
                            _computerYellow,
                            _isBusy
                                ? null
                                : () => _showCpuDifficultyDialog(context),
                            alignment: Alignment.bottomLeft)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _buildArenaGridButton(_homeCyan, null,
                            alignment: Alignment.bottomRight)),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return InkWell(
                  onTap: _isBusy || _isLoadingProfile
                      ? null
                      : () {
                          _playUiTap();
                          _startRandomMatch(context);
                        },
                  borderRadius: BorderRadius.circular(84),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F0F13),
                      border: Border.all(
                        color: const Color(0xFF0F0F13),
                        width: 5,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF171125),
                          border: Border.all(
                            color: _rankedPurple,
                            width: 2.4,
                          )),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'ランク戦',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _rankedPurpleText,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _rankedPurple.withValues(alpha: 0.82),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HexagonTrophyIcon(size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    _isLoadingProfile ? '...' : '$_rating',
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ModeButtonBorderOverlayPainter(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridButton(String title, Color accentColor, VoidCallback? onTap,
      {Alignment alignment = Alignment.center}) {
    final textAlign = alignment.x < 0
        ? TextAlign.left
        : alignment.x > 0
            ? TextAlign.right
            : TextAlign.center;

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              _playUiTap();
              onTap();
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
            color: const Color(0xFF111722),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.56),
              width: 2.4,
            )),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              AppSettings.instance.translate(title),
              textAlign: textAlign,
              style: TextStyle(
                color: accentColor.withValues(alpha: 0.96),
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArenaGridButton(Color accentColor, VoidCallback? onTap,
      {Alignment alignment = Alignment.center}) {
    const disabledArenaColor = Color(0xFF676D76);

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              _playUiTap();
              onTap();
            },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
            color: const Color(0xFF151922),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: disabledArenaColor.withValues(alpha: 0.42),
              width: 2.4,
            )),
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: alignment,
              child: const Text(
                'Coming Soon...',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Color(0xFFB8C0CA),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasArenaFinishedRun =>
      !_arenaManager.isArenaActive &&
      (_arenaManager.currentWins >= ArenaManager.maxWins ||
          _arenaManager.currentLosses >= ArenaManager.maxLosses);

  Future<bool> _showArenaReentryDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: 'アリーナ再入場',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_arenaManager.currentWins}勝 ${_arenaManager.currentLosses}敗 の戦績です。\n'
                '再入場しますか？',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildCoinAmount(
                ArenaManager.entryCost,
                color: const Color(0xFFEAF6FF),
                iconSize: 18,
                fontSize: 18,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '再入場',
                      accentColor: _homeCyan,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  Future<bool> _showArenaEntryConfirmDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: 'アリーナ入場',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'アリーナに入場しますか？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildCoinAmount(
                ArenaManager.entryCost,
                color: const Color(0xFFEAF6FF),
                iconSize: 18,
                fontSize: 18,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '入場',
                      accentColor: _homeCyan,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  Future<void> _showArenaEntryRewardsDialog(BuildContext context) {
    final milestones = List<int>.generate(ArenaManager.maxWins + 1, (i) => i);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: 'アリーナ報酬',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '敗北3回で終了 / 12勝で最大報酬',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final wins in milestones) ...[
                        _buildArenaRewardMilestone(wins),
                        if (wins != milestones.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: _homeCyan,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArenaRewardMilestone(int wins) {
    final reward = _arenaManager.previewRewardForWins(wins);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _homeCyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _homeCyanBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: Colors.amberAccent.withValues(alpha: 0.6)),
            ),
            child: Text(
              '$wins勝',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildCoinAmount(
                reward.coins,
                color: const Color(0xFFEAF6FF),
                iconSize: 14,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _missionDisplayTitle(Map<String, dynamic> mission) {
    final id = mission['id']?.toString() ?? '';
    return AppSettings.instance.translate(
      MissionCatalog.localizedTitleForId(id) ??
          mission['title']?.toString() ??
          'ミッション',
    );
  }

  Future<void> _openMissionScreen() async {
    _playUiTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MissionScreen()),
    );
    if (mounted) {
      await _refreshPlayerEconomy();
    }
  }

  Widget _buildBottomBannerTop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      child: Row(
        children: [
          _buildBottomTextButton(
            Icons.storefront,
            'ショップ',
            () => _openDailyShop(context),
          ),
          _buildBottomTextButton(
            Icons.collections_bookmark,
            'コレクション',
            () => unawaited(_openCollectionScreen()),
            showDot: _hasUnseenCollectionItems,
          ),
          _buildBottomTextButton(
            Icons.assignment_turned_in,
            'ミッション',
            () => unawaited(_openMissionScreen()),
            badgeCount: _claimableMissionCount,
          ),
          _buildBottomTextButton(
            Icons.bar_chart,
            'レコード',
            _openRecordScreen,
          ),
        ],
      ),
    );
  }

  Widget _buildInterstitialSkipTicketHomeButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.instance.adsRemoved,
      builder: (context, adsRemoved, child) {
        if (adsRemoved) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<DateTime?>(
          valueListenable: AppSettings.instance.interstitialSkipUntil,
          builder: (context, skipUntil, child) {
            final remaining = AppSettings.instance.remainingInterstitialSkip;
            final active = remaining > Duration.zero;
            final label = active
                ? '広告なし 残り${_formatSkipTicketRemaining(remaining)}'
                : '30分広告なし';
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: InkWell(
                onTap: () {
                  _playUiTap();
                  unawaited(_showInterstitialSkipTicketDialog(context));
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _homeCyan.withValues(alpha: active ? 0.9 : 0.58),
                      width: active ? 1.8 : 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block_rounded,
                        color: active ? Colors.amberAccent : _homeCyan,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'フレンドバトルも無制限',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildCoinAmount(
                        _interstitialSkipTicketCost,
                        iconSize: 17,
                        fontSize: 13,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openExternalUri(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildBottomTextButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    int badgeCount = 0,
    bool showDot = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          _playUiTap();
          onTap();
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: _homeCyan.withValues(alpha: 0.88),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _homeCyan.withValues(alpha: 0.88),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (badgeCount > 0 || showDot)
              Positioned(
                top: -6,
                right: 18,
                child: Container(
                  width: showDot && badgeCount <= 0 ? 9 : null,
                  height: showDot && badgeCount <= 0 ? 9 : null,
                  padding: showDot && badgeCount <= 0
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      color: _friendPink,
                      borderRadius: BorderRadius.circular(999)),
                  child: showDot && badgeCount <= 0
                      ? null
                      : Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInterstitialSkipTicketDialog(BuildContext context) async {
    await _playerDataManager.load();
    if (!context.mounted) {
      return;
    }
    Timer? countdownTimer;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final remaining = AppSettings.instance.remainingInterstitialSkip;
              final hasActiveSkip = remaining > Duration.zero;
              if (hasActiveSkip) {
                countdownTimer ??= Timer.periodic(
                  const Duration(seconds: 1),
                  (_) {
                    if (dialogContext.mounted) {
                      setDialogState(() {});
                    }
                  },
                );
              } else {
                countdownTimer?.cancel();
                countdownTimer = null;
              }
              final canBuy = !hasActiveSkip &&
                  _playerDataManager.coins >= _interstitialSkipTicketCost;
              final buttonLabel = hasActiveSkip
                  ? '適用中'
                  : canBuy
                      ? '30分広告なしを購入'
                      : 'コイン不足';
              return _buildCyberDialog(
                accentColor: _homeCyan,
                title: '30分広告なし',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '30分間、ゲーム後の広告なしで遊べます。\nこの間はフレンドバトルも無制限に遊べます。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (hasActiveSkip)
                      Text(
                        '残り${_formatSkipTicketRemaining(remaining)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _homeCyan,
                          height: 1.4,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '価格 ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _buildCoinAmount(
                          _interstitialSkipTicketCost,
                          color: const Color(0xFFEAF6FF),
                          iconSize: 20,
                          fontSize: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildCyberDialogButton(
                      label: buttonLabel,
                      accentColor: canBuy ? _homeCyan : Colors.white54,
                      onPressed: canBuy
                          ? () => unawaited(
                                _buyInterstitialSkipTicket(
                                  dialogContext,
                                  setDialogState,
                                ),
                              )
                          : () {},
                    ),
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: '閉じる',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      countdownTimer?.cancel();
    }
  }

  Future<void> _buyInterstitialSkipTicket(
    BuildContext dialogContext,
    StateSetter setDialogState,
  ) async {
    try {
      await _playerDataManager.spendCoins(_interstitialSkipTicketCost);
      await AppSettings.instance.activateInterstitialSkip(
        _interstitialSkipTicketDuration,
      );
      await RankedInterstitialDebtManager.instance.clearAllPending();
      await _refreshPlayerEconomy();
      if (dialogContext.mounted) {
        setDialogState(() {});
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      await _showAlert(context, 'コイン不足', 'コインが不足しています。');
    }
  }

  String _formatSkipTicketRemaining(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
    }
    return '$seconds秒';
  }

  Future<void> _enableAdsFromAdRemovalDialog(
    BuildContext dialogContext,
  ) async {
    await AppSettings.instance.setAdsRemoved(false);
    unawaited(RewardedAdManager.instance.warmUp());
    unawaited(InterstitialAdManager.instance.warmUp());
    if (dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
    if (!mounted) {
      return;
    }
    await _showAlert(
      context,
      '広告設定',
      '広告表示を再度有効にしました。',
    );
  }

  Future<void> _showAdRemovalDialog(BuildContext context) async {
    if (!AdRemovalPurchaseManager.isSupportedPlatform) {
      await _showAdRemovalGiftCodeDialog(context);
      return;
    }
    await _playerDataManager.load();
    await AdRemovalPurchaseManager.instance.initialize();
    final product = AdRemovalPurchaseManager.instance.product;
    final priceLabel = product?.price;
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: '広告削除',
          child: ValueListenableBuilder<bool>(
            valueListenable: AppSettings.instance.adsRemoved,
            builder: (context, adsRemoved, child) {
              if (adsRemoved) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '広告削除は有効です。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildAdRemovalBenefitLine('広告の完全削除'),
                    _buildAdRemovalBenefitLine('毎日1回の無料ガチャ'),
                    _buildAdRemovalBenefitLine('無制限のフレンド対戦'),
                    _buildAdRemovalBenefitLine('対戦後のコイン報酬が毎回3倍に'),
                    _buildAdRemovalBenefitLine('デイリーミッションのコイン獲得量が2倍に'),
                    const SizedBox(height: 16),
                    _buildCyberDialogButton(
                      label: '広告を再度つける',
                      accentColor: _homeCyan,
                      onPressed: () => unawaited(_enableAdsFromAdRemovalDialog(
                        dialogContext,
                      )),
                    ),
                    const SizedBox(height: 12),
                    _buildCyberDialogButton(
                      label: '閉じる',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    priceLabel == null ? '価格を取得中...' : '価格 $priceLabel',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _homeCyan,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '購入すると、以下の特典が有効になります。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAdRemovalBenefitLine('広告の完全削除'),
                  _buildAdRemovalBenefitLine('毎日1回の無料ガチャ'),
                  _buildAdRemovalBenefitLine('無制限のフレンド対戦'),
                  _buildAdRemovalBenefitLine('対戦後のコイン報酬が毎回3倍に'),
                  _buildAdRemovalBenefitLine('デイリーミッションのコイン獲得量が2倍に'),
                  const SizedBox(height: 16),
                  if (AdRemovalPurchaseManager.instance.isConfigured) ...[
                    _buildCyberDialogButton(
                      label: priceLabel == null
                          ? '広告削除を購入する'
                          : '広告削除を購入する $priceLabel',
                      accentColor: _homeCyan,
                      onPressed: () async {
                        final started =
                            await AdRemovalPurchaseManager.instance.buy();
                        if (!started && mounted) {
                          final detail = AdRemovalPurchaseManager
                              .instance.lastInitializationError;
                          await _showAlert(
                            this.context,
                            '購入エラー',
                            detail == null || detail.isEmpty
                                ? '購入を開始できませんでした。しばらくしてからお試しください。'
                                : '購入を開始できませんでした。\n$detail',
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: '購入を復元',
                      accentColor: Colors.white54,
                      onPressed: () => unawaited(
                        AdRemovalPurchaseManager.instance.restore(),
                      ),
                    ),
                  ] else
                    const Text(
                      '広告削除の購入は現在準備中です。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 14),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: Colors.white54,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showAdRemovalGiftCodeDialog(BuildContext context) async {
    final giftCodeController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return _buildCyberDialog(
            accentColor: _homeCyan,
            title: 'ギフトコード',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.instance.adsRemoved,
                  builder: (context, adsRemoved, child) {
                    if (!adsRemoved) {
                      return const SizedBox.shrink();
                    }
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        '広告削除は有効です。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _homeCyan,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    );
                  },
                ),
                TextField(
                  controller: giftCodeController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'ギフトコード',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _homeCyanBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: _homeCyanBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildCyberDialogButton(
                  label: 'コードを使う',
                  accentColor: _homeCyan,
                  onPressed: () async {
                    final redeemed =
                        await AppSettings.instance.redeemAdRemovalGiftCode(
                      code: giftCodeController.text,
                    );
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (!mounted) {
                      return;
                    }
                    await _showAlert(
                      this.context,
                      redeemed ? '広告削除' : 'コードエラー',
                      redeemed ? 'ギフトコードを適用しました。' : 'このコードは無効、または使用済みです。',
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildCyberDialogButton(
                  label: '閉じる',
                  accentColor: Colors.white54,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      giftCodeController.dispose();
    }
  }

  Widget _buildAdRemovalBenefitLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_rounded,
              color: _homeCyan,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startGame(
    BuildContext context,
    bool isCpuMode, {
    CPUDifficulty cpuDifficulty = CPUDifficulty.hard,
  }) async {
    final available = await _ensureModeAvailable(
      context,
      isCpuMode ? MaintenanceMode.cpu : MaintenanceMode.endless,
    );
    if (!available || !mounted || !context.mounted) {
      return;
    }
    final debtKind = isCpuMode
        ? InterstitialDebtKind.computer
        : InterstitialDebtKind.endless;
    final allowed = await _consumePendingInterstitialBeforeStart(
      context,
      kinds: [debtKind],
    );
    if (!allowed || !mounted || !context.mounted) {
      return;
    }
    if (!isCpuMode) {
      unawaited(_missionManager.recordEvent('play_endless'));
    }
    unawaited(_stopHomeBgm());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameScreen(
          isCpuMode: isCpuMode,
          cpuDifficulty: cpuDifficulty,
        ),
      ),
    );
  }

  Future<bool> _ensureModeAvailable(
    BuildContext context,
    MaintenanceMode mode,
  ) async {
    final notice = await AppMaintenanceManager.checkModeAvailability(mode);
    if (!mounted || !context.mounted) {
      return false;
    }
    if (!notice.enabled) {
      return true;
    }
    await _showAlert(context, notice.title, _modeMaintenanceMessage(notice));
    return false;
  }

  String _modeMaintenanceMessage(MaintenanceNotice notice) {
    final expectedEnd = notice.expectedEndAt;
    if (expectedEnd == null) {
      return notice.message;
    }
    final expectedText = '${expectedEnd.month.toString().padLeft(2, '0')}/'
        '${expectedEnd.day.toString().padLeft(2, '0')} '
        '${expectedEnd.hour.toString().padLeft(2, '0')}:'
        '${expectedEnd.minute.toString().padLeft(2, '0')}ごろ再開予定';
    return '${notice.message}\n$expectedText';
  }

  Future<void> _showEndlessStartDialog(BuildContext context) {
    final highScore = _playerDataManager.highestEndlessScore;
    final weeklyScore = _playerDataManager.seasonEndlessHighScore;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _endlessGreen,
          title: 'エンドレス',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ハイスコアに挑戦しますか？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _endlessGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _endlessGreen.withValues(alpha: 0.48),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildEndlessStartScoreValue(
                            label: '今週のスコア',
                            value: weeklyScore,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 46,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: _endlessGreen.withValues(alpha: 0.28),
                        ),
                        Expanded(
                          child: _buildEndlessStartScoreValue(
                            label: 'ハイスコア',
                            value: highScore,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '開始',
                      accentColor: _endlessGreen,
                      onPressed: () async {
                        final available = await _ensureModeAvailable(
                          context,
                          MaintenanceMode.endless,
                        );
                        if (!available || !context.mounted) {
                          return;
                        }
                        Navigator.of(dialogContext).pop();
                        unawaited(_startGame(context, false));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEndlessStartScoreValue({
    required String label,
    required int value,
  }) {
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _endlessGreen.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${_formatScoreNumber(value)}点',
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  String _formatScoreNumber(int value) {
    final digits = value.toString();
    return digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  Future<void> _showCpuDifficultyDialog(BuildContext context) {
    const options = [
      (
        label: '弱い',
        subtitle: 'ゆっくり考えて、よく迷う',
        difficulty: CPUDifficulty.easy,
        color: _computerYellow,
        level: '入門'
      ),
      (
        label: '普通',
        subtitle: 'ほどよく考える標準コンピュータ',
        difficulty: CPUDifficulty.normal,
        color: _computerYellow,
        level: '標準'
      ),
      (
        label: '強い',
        subtitle: '速く読んでミスが少ない',
        difficulty: CPUDifficulty.hard,
        color: _computerYellow,
        level: '上級'
      ),
      (
        label: '鬼',
        subtitle: '最速でほぼ最適解を狙う',
        difficulty: CPUDifficulty.oni,
        color: _computerYellow,
        level: '最強'
      ),
    ];

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _computerYellow,
          title: 'コンピュータ対戦',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options) ...[
                _buildCpuDifficultyTile(
                  label: option.label,
                  subtitle: option.subtitle,
                  accentColor: option.color,
                  level: option.level,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    unawaited(
                      _startGame(
                        context,
                        true,
                        cpuDifficulty: option.difficulty,
                      ),
                    );
                  },
                ),
                if (option != options.last) const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              _buildCyberDialogButton(
                label: 'キャンセル',
                accentColor: _computerYellow,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCpuDifficultyTile({
    required String label,
    required String subtitle,
    required Color accentColor,
    required String level,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        _playUiTap();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF101827).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.48)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          level,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: accentColor),
          ],
        ),
      ),
    );
  }

  Future<void> _showFriendBattleDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _friendPink,
          title: 'フレンド対戦',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '部屋を作成',
                      accentColor: _friendPink,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_createRoom());
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '部屋に参加',
                      accentColor: _friendPink,
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        unawaited(_joinRoom());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildCyberDialogButton(
                label: 'キャンセル',
                accentColor: Colors.white54,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDailyShop(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShopScreen()),
    );
    await _refreshPlayerEconomy();
  }

  // ignore: unused_element
  Future<void> _showDailyMissionsDialog(BuildContext context) async {
    await _refreshPlayerEconomy();
    if (!context.mounted) return;

    var selectedTabIndex = 0;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshDialogState() async {
              await _refreshPlayerEconomy();
              await _missionManager.load();
              if (!mounted) {
                return;
              }
              setDialogState(() {});
            }

            final dialogMissions = _playerDataManager.currentMissions;
            final adsRemoved = AppSettings.instance.adsRemoved.value;
            final showAllClearBonus = !adsRemoved && dialogMissions.isNotEmpty;
            final canClaimAllClearBonus = showAllClearBonus &&
                _missionManager.allMissionsComplete &&
                !_missionManager.isAllClearBonusClaimed;
            final maxDialogHeight = MediaQuery.of(context).size.height * 0.78;

            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: 'ミッション',
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxDialogHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMissionTabSelector(
                      selectedIndex: selectedTabIndex,
                      onChanged: (index) {
                        _playUiTap();
                        setDialogState(() {
                          selectedTabIndex = index;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: selectedTabIndex == 0
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_completedMissionCount / ${dialogMissions.length} 達成',
                                    style: const TextStyle(
                                      color: _homeCyan,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  for (var i = 0;
                                      i < dialogMissions.length;
                                      i++) ...[
                                    _buildSimplifiedMissionTile(
                                      index: i,
                                      mission: dialogMissions[i],
                                      onClaimed: (amount) async {
                                        await refreshDialogState();
                                        if (context.mounted && amount > 0) {
                                          await _showCoinRewardAlert(
                                            context,
                                            'ミッション報酬',
                                            amount,
                                          );
                                        }
                                      },
                                    ),
                                    if (i != dialogMissions.length - 1)
                                      const SizedBox(height: 10),
                                  ],
                                  if (showAllClearBonus) ...[
                                    const SizedBox(height: 14),
                                    _buildDailyAllClearBonusCard(
                                      canClaim: canClaimAllClearBonus,
                                      alreadyClaimed: _missionManager
                                          .isAllClearBonusClaimed,
                                      onClaimed: () async {
                                        await refreshDialogState();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        await _showCoinRewardAlert(
                                          context,
                                          '全達成ボーナス',
                                          _missionManager.allClearClaimAmount,
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              )
                            : FutureBuilder<List<Map<String, dynamic>>>(
                                future: _missionManager.regularMissions(),
                                builder: (context, snapshot) {
                                  final regularMissions =
                                      snapshot.data ?? const [];
                                  if (regularMissions.isEmpty) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Text(
                                        'ミッションを読み込み中...',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0;
                                          i < regularMissions.length;
                                          i++) ...[
                                        _buildRegularMissionTile(
                                          mission: regularMissions[i],
                                          onClaimed: (amount) async {
                                            await refreshDialogState();
                                            if (context.mounted && amount > 0) {
                                              await _showCoinRewardAlert(
                                                context,
                                                'ミッション報酬',
                                                amount,
                                              );
                                            }
                                          },
                                        ),
                                        if (i != regularMissions.length - 1)
                                          const SizedBox(height: 10),
                                      ],
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildCyberDialogButton(
                      label: '閉じる',
                      accentColor: _homeCyan,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMissionTabSelector({
    required int selectedIndex,
    required ValueChanged<int> onChanged,
  }) {
    const labels = ['デイリー', 'レギュラー'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _homeCyanBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: selectedIndex == i ? null : () => onChanged(i),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selectedIndex == i
                        ? _homeCyan.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color:
                          selectedIndex == i ? _homeCyan : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    AppSettings.instance.translate(labels[i]),
                    style: TextStyle(
                      color: selectedIndex == i ? _homeCyan : Colors.white70,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegularMissionTile({
    required Map<String, dynamic> mission,
    required Future<void> Function(int amount) onClaimed,
  }) {
    final progress = (mission['progress'] as num?)?.toInt() ?? 0;
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final reward = (mission['rewardCoins'] as num?)?.toInt() ?? 0;
    final canClaim = mission['claimable'] as bool? ?? false;
    final progressKey = mission['progressKey']?.toString() ?? '';

    return InkWell(
      onTap: !canClaim
          ? null
          : () async {
              _playUiTap();
              final amount = await _missionManager.claimRegularMissionReward(
                mission['id']?.toString() ?? '',
              );
              await onClaimed(amount);
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: canClaim
              ? GameThemeColors.blueSide.withValues(alpha: 0.14)
              : _homeCyan.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: canClaim ? GameThemeColors.blueSide : _homeCyan,
            width: canClaim ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildRegularMissionTitle(mission),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: canClaim
                        ? GameThemeColors.blueSide.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: canClaim
                          ? GameThemeColors.blueSide
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canClaim) ...[
                        const Text(
                          '受け取る',
                          style: TextStyle(
                            color: GameThemeColors.blueSide,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      _buildCoinAmount(
                        reward,
                        color: canClaim
                            ? GameThemeColors.blueSide
                            : Colors.white70,
                        iconSize: 13,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: target == 0 ? 0 : (progress / target).clamp(0, 1),
                    color: canClaim ? GameThemeColors.blueSide : _homeCyan,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(width: 10),
                _buildRegularMissionProgress(
                  progress: progress,
                  target: target,
                  progressKey: progressKey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularMissionTitle(Map<String, dynamic> mission) {
    final progressKey = mission['progressKey']?.toString() ?? '';
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final title = AppSettings.instance.translate(
      mission['title']?.toString() ?? 'ミッション',
    );
    if (progressKey == 'daily_win_rank_1') {
      return Text(
        AppSettings.instance.text(
          '今日の勝利数ランキングで1位を$target回達成する',
          'Finish 1st in today\'s wins ranking $target time${target == 1 ? '' : 's'}',
        ),
        style: const TextStyle(
          color: _homeCyan,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    final parts = title.split('〇〇');
    if (progressKey != 'highest_rating' || parts.length < 2) {
      return Text(
        title.replaceFirst('〇〇', '$target'),
        style: const TextStyle(
          color: _homeCyan,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          parts.first,
          style: const TextStyle(
            color: _homeCyan,
            fontWeight: FontWeight.bold,
          ),
        ),
        HexagonTrophyAmount(
          target,
          iconSize: 14,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
        Text(
          parts.skip(1).join('〇〇'),
          style: const TextStyle(
            color: _homeCyan,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRegularMissionProgress({
    required int progress,
    required int target,
    required String progressKey,
  }) {
    final cappedProgress = math.min(progress, target);
    if (progressKey == 'highest_rating') {
      return HexagonTrophyAmount(
        cappedProgress,
        suffix: ' / $target',
        color: Colors.white70,
        iconSize: 13,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
    }
    return Text(
      '$cappedProgress / $target',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Widget _buildSimplifiedMissionTile({
    required int index,
    required Map<String, dynamic> mission,
    required Future<void> Function(int amount) onClaimed,
  }) {
    final progress = (mission['progress'] as num?)?.toInt() ?? 0;
    final target = (mission['target'] as num?)?.toInt() ?? 0;
    final reward = _missionManager.rewardCoinsFor(mission);
    final claimed = mission['claimed'] as bool? ?? false;
    final adsRemoved = AppSettings.instance.adsRemoved.value;
    final missionId = mission['id']?.toString() ?? '';
    final isRewardedAdMission = MissionCatalog.isRewardedAdMissionId(missionId);
    final isDone = progress >= target;
    final canClaim =
        (isDone || (isRewardedAdMission && adsRemoved)) && !claimed;
    final stateColor = claimed ? GameThemeColors.blueSide : _homeCyan;
    final displayTitle = isRewardedAdMission && adsRemoved
        ? 'ログインボーナス'
        : _missionDisplayTitle(mission);
    final isLoginRewardMission =
        MissionCatalog.isLoginRewardMissionId(missionId);
    final canReroll =
        !claimed && !canClaim && !isRewardedAdMission && !isLoginRewardMission;

    return InkWell(
      onTap: claimed || (!canClaim && !isRewardedAdMission)
          ? null
          : () async {
              _playUiTap();
              if (isRewardedAdMission && !canClaim) {
                if (!adsRemoved) {
                  final rewarded =
                      await RewardedAdManager.instance.showDoubleRewardAd();
                  if (!rewarded) {
                    if (mounted) {
                      await _showAlert(
                        context,
                        '広告エラー',
                        '動画の視聴が完了しませんでした。',
                      );
                    }
                    return;
                  }
                }
                if (mounted && context.mounted) {
                  await _showCoinRewardAlert(
                    context,
                    'ミッション報酬',
                    reward,
                  );
                }
                await _missionManager.completeRewardedAdMissionById(missionId);
                await onClaimed(0);
                return;
              }
              final amount = isRewardedAdMission && adsRemoved
                  ? await _missionManager.completeRewardedAdMissionById(
                      missionId,
                    )
                  : await _missionManager.claimMissionRewardById(missionId);
              await onClaimed(amount);
            },
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: claimed
                  ? GameThemeColors.blueSide.withValues(alpha: 0.14)
                  : canClaim
                      ? _homeCyan.withValues(alpha: 0.12)
                      : isRewardedAdMission && !claimed
                          ? _homeCyan.withValues(alpha: 0.12)
                          : isDone
                              ? _homeCyan.withValues(alpha: 0.15)
                              : _homeCyan.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: claimed
                    ? GameThemeColors.blueSide
                    : canClaim
                        ? _homeCyan
                        : isRewardedAdMission && !claimed
                            ? _homeCyan
                            : isDone
                                ? _homeCyan
                                : _homeCyan,
                width: canClaim ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isRewardedAdMission && !adsRemoved) ...[
                      Icon(
                        Icons.play_circle_fill_rounded,
                        size: 18,
                        color: stateColor,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        displayTitle,
                        style: TextStyle(
                          color: stateColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: claimed
                            ? GameThemeColors.blueSide.withValues(alpha: 0.12)
                            : canClaim
                                ? GameThemeColors.blueSide
                                    .withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: claimed
                              ? GameThemeColors.blueSide.withValues(alpha: 0.75)
                              : canClaim
                                  ? GameThemeColors.blueSide
                                  : Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      child: _buildMissionRewardBadgeContent(
                        reward: reward,
                        claimed: claimed,
                        canClaim: canClaim,
                        isRewardedAdMission: isRewardedAdMission,
                      ),
                    ),
                    if (canReroll) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          _playUiTap();
                          if (!adsRemoved) {
                            final rewarded = await RewardedAdManager.instance
                                .showDoubleRewardAd();
                            if (!rewarded) {
                              if (mounted) {
                                await _showAlert(
                                  context,
                                  '広告エラー',
                                  '動画の視聴が完了しませんでした。',
                                );
                              }
                              return;
                            }
                          }
                          try {
                            await _missionManager.rerollMissionById(missionId);
                            await onClaimed(0);
                          } catch (error) {
                            if (mounted) {
                              await _showAlert(context, 'ERROR', '$error');
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 46,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _homeCyan.withValues(alpha: 0.24),
                                  Colors.purpleAccent.withValues(alpha: 0.22),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _homeCyanBorder,
                              )),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (adsRemoved)
                                const Icon(
                                  Icons.sync_rounded,
                                  color: _homeCyan,
                                  size: 20,
                                )
                              else
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.sync_rounded,
                                      color: _homeCyan,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 2),
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.72),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _homeCyanBorder.withValues(
                                            alpha: 0.72,
                                          ),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: _homeCyan,
                                        size: 12,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value:
                            target == 0 ? 0 : (progress / target).clamp(0, 1),
                        color: stateColor,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$progress / $target',
                      style: TextStyle(color: stateColor, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAllClearBonusCard({
    required bool canClaim,
    required bool alreadyClaimed,
    required Future<void> Function() onClaimed,
  }) {
    return InkWell(
      onTap: !canClaim
          ? null
          : () async {
              _playUiTap();
              final rewarded =
                  await RewardedAdManager.instance.showDoubleRewardAd();
              if (!rewarded) {
                if (mounted) {
                  await _showAlert(
                    context,
                    '広告エラー',
                    '動画の視聴が完了しませんでした。',
                  );
                }
                return;
              }
              final amount = await _missionManager.claimAllClearBonus();
              if (amount > 0) {
                await onClaimed();
              }
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: canClaim
              ? _homeCyan.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canClaim ? _homeCyan : Colors.white.withValues(alpha: 0.2),
            width: canClaim ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              alreadyClaimed
                  ? Icons.check_circle_rounded
                  : Icons.ondemand_video_rounded,
              color: canClaim ? _homeCyan : Colors.white54,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alreadyClaimed ? '全達成ボーナス受取済み' : '全達成ボーナス',
                    style: TextStyle(
                      color: canClaim ? _homeCyan : Colors.white70,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alreadyClaimed
                        ? '本日の受け取りは完了しています'
                        : canClaim
                            ? '動画広告を見ると今日の追加報酬を受け取れます'
                            : '4つすべて達成すると動画広告で受け取れます',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildCoinAmount(
              _missionManager.allClearClaimAmount,
              color: canClaim ? const Color(0xFFEAF6FF) : Colors.white54,
              iconSize: 16,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionRewardBadgeContent({
    required int reward,
    required bool claimed,
    required bool canClaim,
    required bool isRewardedAdMission,
  }) {
    if (claimed) {
      return const Text(
        '受取済み',
        style: TextStyle(
          color: GameThemeColors.blueSide,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      );
    }
    if (isRewardedAdMission && !canClaim) {
      return _buildCoinAmount(
        reward,
        color: Colors.white70,
        iconSize: 13,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canClaim)
          const Text(
            '受け取る',
            style: TextStyle(
              color: GameThemeColors.blueSide,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        if (canClaim) const SizedBox(width: 5),
        _buildCoinAmount(
          reward,
          color: canClaim ? GameThemeColors.blueSide : Colors.white70,
          iconSize: 13,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _startArenaMatch(BuildContext context) async {
    if (_isBusy) {
      return;
    }

    final available = await _ensureModeAvailable(
      context,
      MaintenanceMode.arena,
    );
    if (!available || !mounted || !context.mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    var dialogOpen = false;
    try {
      if (!await _ensureRealtimeConnectionForMatchmaking(
        context,
        title: 'アリーナマッチ失敗',
      )) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await _arenaManager.load();
      if (!_arenaManager.isArenaActive) {
        if (_hasArenaFinishedRun) {
          if (!context.mounted) {
            return;
          }
          final shouldReenter = await _showArenaReentryDialog(context);
          if (!shouldReenter) {
            return;
          }
        } else {
          if (!context.mounted) {
            return;
          }
          final shouldEnter = await _showArenaEntryConfirmDialog(context);
          if (!shouldEnter) {
            return;
          }
        }
        try {
          await _arenaManager.enterArena();
          await _missionManager.recordEvent('enter_arena');
        } catch (error) {
          if (!context.mounted) {
            return;
          }
          await _showAlert(context, '不足しています', '$error');
          return;
        }
        await _refreshPlayerEconomy();
        if (!context.mounted) {
          return;
        }
        await _showArenaEntryRewardsDialog(context);
        return;
      }
      if (!context.mounted) {
        return;
      }

      final currentWins = _arenaManager.currentWins;
      final currentReward =
          _arenaManager.previewRewardForWins(currentWins).coins;
      dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: 'アリーナ',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_arenaManager.currentWins}勝 ${_arenaManager.currentLosses}敗',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '現在報酬',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildCoinAmount(
                        currentReward,
                        color: const Color(0xFFEAF6FF),
                        iconSize: 18,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '対戦相手を検索中...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: _homeCyan,
                        backgroundColor: _homeCyan.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildCyberDialogButton(
                    label: 'キャンセル',
                    accentColor: _homeCyan,
                    onPressed: () {
                      unawaited(_multiplayerManager.cancelArenaMatchmaking());
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              ),
            );
          },
        ).then((_) {
          dialogOpen = false;
        }),
      );

      await Future<void>.delayed(Duration.zero);
      final roomId = await _multiplayerManager.startArenaMatch(currentWins);
      if (!context.mounted) {
        return;
      }

      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (roomId == null) {
        return;
      }

      unawaited(_stopHomeBgm());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: roomId,
            isHost: _multiplayerManager.isHost,
            isRankedMode: true,
            isArenaMode: true,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _showAlert(context, 'アリーナマッチ失敗', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
      unawaited(_multiplayerManager.cancelArenaMatchmaking());
    }
  }

  Future<void> _loadPlayerName() async {
    final savedName = await _readSavedPlayerName();
    if (!mounted) {
      return;
    }

    setState(() {
      _playerNameController.text = savedName;
    });
    if (savedName.trim().isNotEmpty) {
      _multiplayerManager.setPlayerName(savedName);
      await _playerDataManager.setPlayerName(savedName);
    }

    try {
      final rating = await _multiplayerManager
          .initializeUser(name: savedName)
          .timeout(_nameRegistrationSyncTimeout);
      _multiplayerManager.currentRating = rating;
      await _syncRankedSeasonState(showResultLog: true)
          .timeout(_nameRegistrationSyncTimeout);
      await _syncPlayerProfileOnline(rating: _playerDataManager.currentRating);
      if (!mounted) {
        return;
      }
      setState(() {
        _rating = _playerDataManager.currentRating;
        _isLoadingProfile = false;
      });
      _scheduleInitialNameRegistrationIfNeeded();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rating = _playerDataManager.currentRating;
        _isLoadingProfile = false;
      });
      _scheduleInitialNameRegistrationIfNeeded();
      unawaited(_syncRankedSeasonState(showResultLog: true));
      unawaited(_syncPlayerProfileOnline(
        rating: _playerDataManager.currentRating,
      ).catchError((_) {}));
    }
  }

  Future<String> _readSavedPlayerName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_playerNameKey) ?? '';
      if (savedName.trim().isNotEmpty) {
        return savedName;
      }
      await _playerDataManager.load();
      return _playerDataManager.displayPlayerName;
    } on MissingPluginException {
      return _playerDataManager.displayPlayerName;
    }
  }

  Future<bool> _ensureRealtimeConnectionForMatchmaking(
    BuildContext context, {
    required String title,
  }) async {
    final currentConnected = await RealtimeConnectionGuard.currentConnected(
      timeout: const Duration(milliseconds: 180),
    );
    if (currentConnected == false) {
      if (context.mounted) {
        await _showAlert(
            context, title, RealtimeConnectionGuard.offlineMessage);
      }
      return false;
    }
    if (currentConnected == true) {
      return true;
    }
    final connected = await RealtimeConnectionGuard.waitForConnected(
      timeout: const Duration(milliseconds: 700),
    );
    if (connected) {
      return true;
    }
    if (context.mounted) {
      await _showAlert(context, title, RealtimeConnectionGuard.offlineMessage);
    }
    return false;
  }

  Future<void> _createRoom() async {
    final available = await _ensureModeAvailable(
      context,
      MaintenanceMode.friend,
    );
    if (!available || !mounted) {
      return;
    }
    final hasAllowance = await _ensureFriendMatchAllowance();
    if (!mounted || !hasAllowance) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await _multiplayerManager.createRoom();
      if (!mounted) {
        return;
      }
      final consumed = await FriendMatchLimitManager.instance.consumeMatch();
      if (!consumed) {
        await _multiplayerManager.cancelLobby();
        if (!mounted) {
          return;
        }
        await _showAlert(
          context,
          'フレンド対戦',
          '本日の無料フレンド対戦回数を使い切りました。',
        );
        return;
      }
      if (!mounted) {
        return;
      }

      unawaited(_stopHomeBgm());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: _multiplayerManager.currentRoomId,
            isHost: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showAlert(context, 'ルーム作成に失敗しました', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _joinRoom() async {
    final available = await _ensureModeAvailable(
      context,
      MaintenanceMode.friend,
    );
    if (!available || !mounted) {
      return;
    }
    final hasAllowance = await _ensureFriendMatchAllowance();
    if (!mounted || !hasAllowance) {
      return;
    }

    final roomId = await _showRoomIdDialog(context);
    if (!mounted || roomId == null) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      final joined = await _multiplayerManager.joinRoom(roomId);
      if (!mounted) {
        return;
      }

      if (!joined) {
        await _showAlert(
          context,
          'ルームに参加できません',
          '部屋が見つからないか、すでに対戦中です。',
        );
        return;
      }
      final consumed = await FriendMatchLimitManager.instance.consumeMatch();
      if (!consumed) {
        await _multiplayerManager.leaveRoom();
        if (!mounted) {
          return;
        }
        await _showAlert(
          context,
          'フレンド対戦',
          '本日の無料フレンド対戦回数を使い切りました。',
        );
        return;
      }
      if (!mounted) {
        return;
      }

      unawaited(_stopHomeBgm());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: roomId,
            isHost: false,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showAlert(context, '接続エラー', '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<bool> _ensureFriendMatchAllowance() async {
    if (await FriendMatchLimitManager.instance.canStartMatch()) {
      return true;
    }
    if (!mounted) {
      return false;
    }

    unawaited(RewardedAdManager.instance.warmUp());
    final shouldWatchAd = await _showFriendMatchRestoreDialog(context);
    if (!mounted || shouldWatchAd != true) {
      return false;
    }

    final rewarded = await RewardedAdManager.instance.showDoubleRewardAd();
    if (!mounted) {
      return false;
    }
    if (!rewarded) {
      await _showAlert(context, '広告エラー', '動画の視聴が完了しませんでした。');
      return false;
    }

    await FriendMatchLimitManager.instance.addRewardedMatches();
    if (!mounted) {
      return true;
    }
    await _showAlert(
      context,
      'フレンド対戦',
      'フレンド対戦が2戦分回復しました。',
    );
    return true;
  }

  Future<bool?> _showFriendMatchRestoreDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _friendPink,
          title: 'フレンド対戦',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '本日の無料フレンド対戦回数を使い切りました。\n動画広告を見ると2戦分回復します。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '動画を見る',
                      accentColor: _friendPink,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startRandomMatch(
    BuildContext context, {
    bool isArenaMode = false,
  }) async {
    if (_isBusy) {
      return;
    }
    final available = await _ensureModeAvailable(
      context,
      isArenaMode ? MaintenanceMode.arena : MaintenanceMode.ranked,
    );
    if (!available || !mounted || !context.mounted) {
      return;
    }
    setState(() {
      _isBusy = true;
    });

    var dialogOpen = false;
    var cancelledByUser = false;
    try {
      if (!await _consumePendingRankedInterstitialBeforeMatch(
        context,
        isArenaMode: isArenaMode,
      )) {
        return;
      }
      if (!context.mounted || cancelledByUser) {
        return;
      }

      dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return _buildCyberDialog(
              accentColor: _rankedPurple,
              title: 'ランク戦',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '対戦相手を検索中...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: _rankedPurple,
                        backgroundColor: _rankedPurple.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  const _RankedMatchmakingEstimate(),
                  const SizedBox(height: 14),
                  const _RankedMatchmakingHint(),
                  const SizedBox(height: 24),
                  _buildCyberDialogButton(
                    label: 'キャンセル',
                    accentColor: _rankedPurple,
                    onPressed: () {
                      cancelledByUser = true;
                      unawaited(_multiplayerManager.cancelMatchmaking());
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              ),
            );
          },
        ).then((_) {
          dialogOpen = false;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      if (cancelledByUser) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      if (!await _ensureRealtimeConnectionForMatchmaking(
        context,
        title: 'ランク戦に失敗しました',
      )) {
        if (context.mounted && dialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogOpen = false;
        }
        return;
      }
      if (!context.mounted) {
        return;
      }
      await _syncRankedSeasonState().timeout(_nameRegistrationSyncTimeout);
      if (!context.mounted || cancelledByUser) {
        return;
      }
      await _missionManager.recordEvent('start_ranked_match');
      if (cancelledByUser) {
        return;
      }
      final seasonRating = _playerDataManager.currentRating;
      _multiplayerManager.currentRating = seasonRating;
      if (mounted) {
        setState(() {
          _rating = seasonRating;
        });
      }
      final roomId = await _multiplayerManager.startRandomMatch(seasonRating);
      if (!context.mounted) {
        return;
      }
      if (cancelledByUser) {
        await _multiplayerManager.cancelMatchmaking();
        return;
      }

      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }

      if (roomId == null) {
        return;
      }

      if (!isArenaMode) {
        await RankedInterstitialDebtManager.instance.clearPending();
      }
      if (!context.mounted) {
        return;
      }

      unawaited(_stopHomeBgm());
      if (_multiplayerManager.isRankedBotRoomId(roomId)) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => GameScreen(
              isCpuMode: true,
              isRankedMode: true,
              cpuDifficulty:
                  _multiplayerManager.rankedBotDifficulty ?? CPUDifficulty.hard,
              rankedBotRating: _multiplayerManager.rankedBotRating,
              rankedBotName: 'プレイヤー',
              rankedBotIconId: _multiplayerManager.rankedBotIconId,
              rankedBotFrameId: _multiplayerManager.rankedBotFrameId,
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen.online(
            roomId: roomId,
            isHost: _multiplayerManager.isHost,
            isRankedMode: true,
            isArenaMode: isArenaMode,
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _showAlert(
        context,
        'ランク戦に失敗しました',
        'マッチングに失敗しました。再度やり直してください。',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _rating = _multiplayerManager.currentRating;
        });
      }
      unawaited(_multiplayerManager.cancelMatchmaking());
    }
  }

  Future<bool> _consumePendingRankedInterstitialBeforeMatch(
    BuildContext context, {
    required bool isArenaMode,
  }) async {
    if (isArenaMode) {
      return true;
    }
    return _consumePendingInterstitialBeforeStart(
      context,
      kinds: const [
        InterstitialDebtKind.rankedHuman,
        InterstitialDebtKind.rankedBot,
      ],
    );
  }

  Future<bool> _consumePendingInterstitialBeforeStart(
    BuildContext context, {
    required List<InterstitialDebtKind> kinds,
  }) async {
    InterstitialDebtKind? pendingKind;
    for (final kind in kinds) {
      if (await RankedInterstitialDebtManager.instance.hasPending(kind: kind)) {
        pendingKind = kind;
        break;
      }
    }
    if (pendingKind == null) {
      return true;
    }
    final shown = await InterstitialAdManager.instance.showRequired();
    if (shown) {
      await RankedInterstitialDebtManager.instance.clearPending(
        kind: pendingKind,
      );
      await InterstitialAdManager.instance.settleAfterGame();
      return true;
    }

    unawaited(InterstitialAdManager.instance.warmUp());
    if (!context.mounted) {
      return false;
    }
    await _showAlert(
      context,
      '広告の読み込みに失敗しました',
      '広告を表示できませんでした。しばらくしてからもう一度お試しください。',
    );
    return false;
  }

  Future<void> _maybeResumeSavedOnlineSession() async {
    final resolution = await _multiplayerManager.inspectSavedSession();
    if (!mounted || resolution == null) {
      return;
    }

    if (resolution.newRating != null) {
      _multiplayerManager.currentRating = resolution.newRating!;
      unawaited(_playerDataManager.setCurrentRating(resolution.newRating!));
      unawaited(
        _rankingManager.updateMyRating(rating: resolution.newRating!),
      );
    }
    final arenaTransition =
        await _applyResolvedOnlineSessionLocally(resolution);
    await _multiplayerManager.clearSavedSession();
    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }
    setState(() {
      _rating = resolution.newRating ?? _multiplayerManager.currentRating;
    });
    unawaited(_refreshRankingSummary(forceRefresh: true));
    if (resolution.wasAbandoned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          _showAlert(
            context,
            '試合放棄',
            _abandonedMatchMessage(
              resolution,
              arenaTransition: arenaTransition,
            ),
          ),
        );
      });
    }
  }

  String _abandonedMatchMessage(
    SavedSessionResolution resolution, {
    _ArenaRecordTransition? arenaTransition,
  }) {
    final session = resolution.session;
    final modeLabel = session.isArenaMode
        ? 'アリーナ'
        : session.isRankedMode
            ? 'ランク戦'
            : 'フレンド対戦';
    final buffer = StringBuffer(
      resolution.wasOfflineDisconnect
          ? '前回$modeLabel中にデータ通信に接続できなかったため不戦敗となりました。'
          : '前回$modeLabel中にアプリを終了したため試合放棄となりました。',
    );
    final oldRating = resolution.oldRating;
    final newRating = resolution.newRating;
    if (session.isRankedMode &&
        !session.isArenaMode &&
        oldRating != null &&
        newRating != null) {
      buffer.write('\nレート：$oldRating→$newRating');
    }
    if (session.isArenaMode && arenaTransition != null) {
      buffer.write(
        '\nアリーナ：${arenaTransition.beforeWins}勝${arenaTransition.beforeLosses}敗'
        '→${arenaTransition.afterWins}勝${arenaTransition.afterLosses}敗',
      );
    }
    return buffer.toString();
  }

  Future<_ArenaRecordTransition?> _applyResolvedOnlineSessionLocally(
    SavedSessionResolution resolution,
  ) async {
    final isWin = resolution.isWin;
    if (isWin == null) {
      return null;
    }

    final mode = resolution.session.isArenaMode
        ? 'ARENA'
        : resolution.session.isRankedMode
            ? 'RANKED'
            : 'FRIEND';
    await _playerDataManager.recordMatchResult(
      isWin: isWin,
      mode: mode,
      opponentName: resolution.opponentName ?? 'UNKNOWN',
      wazaCounts: const {
        'straight': 0,
        'pyramid': 0,
        'hexagon': 0,
      },
      isForfeitWin: isWin,
      ratingAfter: resolution.newRating,
      ratingDelta: resolution.ratingDelta,
    );
    if (!resolution.session.isArenaMode) {
      return null;
    }
    await _arenaManager.load();
    final beforeWins = _arenaManager.currentWins;
    final beforeLosses = _arenaManager.currentLosses;
    final result = await _arenaManager.recordArenaMatch(isWin);
    return _ArenaRecordTransition(
      beforeWins: beforeWins,
      beforeLosses: beforeLosses,
      afterWins: result.wins,
      afterLosses: result.losses,
    );
  }

  Future<String?> _showRoomIdDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _friendPink,
          title: 'ルーム参加',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                cursorColor: _friendPink,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  hintText: '123456',
                  counterText: '',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.24),
                    letterSpacing: 8,
                  ),
                  filled: true,
                  fillColor: Colors.black.withValues(alpha: 0.35),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _friendPink.withValues(alpha: 0.72),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _friendPink.withValues(alpha: 0.92),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: 'キャンセル',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCyberDialogButton(
                      label: '部屋に参加',
                      accentColor: _friendPink,
                      onPressed: () {
                        final roomId = controller.text.trim();
                        if (RegExp(r'^\d{6}$').hasMatch(roomId)) {
                          Navigator.of(dialogContext).pop(roomId);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAlert(
    BuildContext context,
    String title,
    String message, {
    String buttonLabel = 'OK',
  }) {
    final isSeasonResult = title == 'シーズン結果';
    final isLevelUp = title == 'レベルアップ';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: title,
          child: isSeasonResult
              ? _buildSeasonResultLog(message, dialogContext)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    isLevelUp
                        ? _buildLevelUpAlertMessage(message)
                        : _buildAlertMessage(message),
                    const SizedBox(height: 20),
                    _buildCyberDialogButton(
                      label: buttonLabel,
                      accentColor: _homeCyan,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildLevelUpAlertMessage(String message) {
    final lines = message.split('\n');
    final rewardLine = lines.length > 1 ? lines.sublist(1).join('\n') : '';
    final match = RegExp(
      r'^レベルアップ報酬として(合計 )?(\d+) を獲得しました。$',
    ).firstMatch(rewardLine.trim());
    if (match == null) {
      return Text(
        message,
        style: const TextStyle(color: Colors.white70, height: 1.5),
        textAlign: TextAlign.center,
      );
    }
    final amount = int.tryParse(match.group(2) ?? '') ?? 0;
    final prefix = match.group(1) == null ? '' : '合計 ';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          lines.first,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(
              'レベルアップ報酬として$prefix',
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            _buildCoinAmount(
              amount,
              iconSize: 18,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
            const Text(
              'を獲得しました。',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertMessage(String message) {
    final coinReceived = RegExp(
      r'^([\d,，]+)\s*(?:コイン)?を受け取りました。$',
    ).firstMatch(message.trim());
    if (coinReceived != null) {
      final amountText =
          (coinReceived.group(1) ?? '').replaceAll(RegExp(r'[,，]'), '');
      final amount = int.tryParse(amountText) ?? 0;
      if (amount > 0) {
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            _buildCoinAmount(
              amount,
              iconSize: 18,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
            const Text(
              'を受け取りました。',
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
          ],
        );
      }
    }
    return Text(
      message,
      style: const TextStyle(
        color: Colors.white70,
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSeasonResultLog(String message, BuildContext dialogContext) {
    final result = _SeasonResultViewData.fromLog(message);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _homeCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _homeCyanBorder,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Text(
                result.seasonName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              HexagonTrophyAmount(
                int.tryParse(result.rating) ?? 0,
                color: Colors.amberAccent,
                iconSize: 30,
                fontSize: 34,
              ),
              const SizedBox(height: 4),
              Text(
                'FINAL RATE',
                style: TextStyle(
                  color: _homeCyan.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildSeasonResultMetric('RANK', result.rank)),
            const SizedBox(width: 8),
            Expanded(child: _buildSeasonResultMetric('RECORD', result.record)),
            const SizedBox(width: 8),
            Expanded(
                child: _buildSeasonResultMetric('WIN RATE', result.winRate)),
          ],
        ),
        const SizedBox(height: 20),
        _buildCyberDialogButton(
          label: 'OK',
          accentColor: _homeCyan,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    );
  }

  Widget _buildSeasonResultMetric(String label, String value) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCoinRewardAlert(
    BuildContext context,
    String title,
    int amount,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCoinAmount(
                    amount,
                    color: const Color(0xFFEAF6FF),
                    iconSize: 22,
                    fontSize: 20,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'を受け取りました。',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: _homeCyan,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showHowToDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: '遊び方',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHowToSection(
                    title: '基本ルール',
                    body: '同じ色のボールを6つ以上繋げると消えます。'
                        '消せる場所を探しながら、落ちてくる操作ボールを置いていきましょう。',
                  ),
                  _buildHowToSection(
                    title: '操作',
                    body: '左右移動で位置を合わせ、回転で色の並びを変えます。'
                        '置きたい場所が決まったらドロップして、盤面を素早く整えましょう。'
                        '操作パネルのレイアウトは、設定から変更できます。',
                  ),
                  _buildHowToSection(
                    title: 'フォーメーション',
                    body: '同じ色で特定の形を作るとフォーメーションが発動します。'
                        '発動すると、盤面内にある同じ色のボールをまとめて消せます。',
                  ),
                  _buildHowToSection(
                    title: 'フォーメーションの種類',
                    body: 'ストレート: 同じ色を一直線に並べる基本形です。\n'
                        'ピラミッド: 同じ色を三角形に並べる応用形です。\n'
                        'ヘキサゴン: 同じ色を六角形に並べる強力な形です。',
                  ),
                  _buildHowToSection(
                    title: '対戦',
                    body: '対戦では、フォーメーションを決めると相手に妨害ボールを送れます。'
                        '盤面の上にあるラインをボールが超えるとゲームオーバーです。',
                  ),
                  _buildHowToSection(
                    title: 'モード',
                    body: 'ランク戦: レートをかけて全国のプレイヤーと対戦します。\n'
                        'フレンド対戦: 部屋を作って友達と対戦できます。\n'
                        'コンピュータ対戦: 強さを選んで練習できます。\n'
                        'エンドレス: ひとりでハイスコアに挑戦します。',
                  ),
                  const SizedBox(height: 16),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: _homeCyan,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHowToSection({
    required String title,
    required String body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _homeCyanBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _homeCyan,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOnboardingDemo() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => const GameScreen(isTutorialMode: true),
      ),
    );
  }

  Future<void> _openOnboardingFromSettings(
    BuildContext dialogContext,
  ) async {
    Navigator.of(dialogContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) {
      return;
    }
    await _showOnboardingDemo();
  }

  Future<void> _showSettingsDialog() async {
    double musicVolume = AppSettings.instance.musicVolume.value;
    double sfxVolume = AppSettings.instance.sfxVolume.value;
    var layout = AppSettings.instance.controlLayout.value;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateMusic(double value) async {
              setDialogState(() {
                musicVolume = value;
              });
              await AppSettings.instance.setMusicVolume(value);
              await SeamlessBgm.instance.setMasterVolume(value);
            }

            Future<void> updateSfx(double value) async {
              setDialogState(() {
                sfxVolume = value;
              });
              await AppSettings.instance.setSfxVolume(value);
            }

            Future<void> updateLayout(ControlLayoutPreset preset) async {
              setDialogState(() {
                layout = preset;
              });
              await AppSettings.instance.setControlLayout(preset);
            }

            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: '設定',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCyberDialogButton(
                    label: AppSettings.instance.text('音量設定', 'Audio'),
                    accentColor: _homeCyan,
                    onPressed: () => unawaited(
                      _showAudioSettingsDialog(
                        dialogContext,
                        initialMusicVolume: musicVolume,
                        initialSfxVolume: sfxVolume,
                        onMusicChanged: (value) async {
                          await updateMusic(value);
                        },
                        onSfxChanged: (value) async {
                          await updateSfx(value);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCyberDialogButton(
                    label: AppSettings.instance.text('操作設定', 'Controls'),
                    accentColor: _homeCyan,
                    onPressed: () => unawaited(
                      _showControlSettingsDialog(
                        dialogContext,
                        initialLayout: layout,
                        onLayoutChanged: (preset) async {
                          await updateLayout(preset);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCyberDialogButton(
                    label: AppSettings.instance.text('チュートリアル', 'Tutorial'),
                    accentColor: _homeCyan,
                    onPressed: () => unawaited(
                      _openOnboardingFromSettings(dialogContext),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildCyberDialogButton(
                    label: '招待コード',
                    accentColor: _homeCyan,
                    onPressed: () => unawaited(
                      _showInviteCodeDialog(dialogContext),
                    ),
                  ),
                  if (_showsSettingsAdRemovalActions &&
                      AdRemovalPurchaseManager.isSupportedPlatform) ...[
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: AppSettings.instance.text('広告削除', 'Remove Ads'),
                      accentColor: _homeCyan,
                      onPressed: () => unawaited(
                        _showAdRemovalDialog(dialogContext),
                      ),
                    ),
                  ],
                  if (_showsSettingsAdRemovalActions &&
                      AppReviewConfig.adRemovalGiftCodeEnabled) ...[
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: AppSettings.instance.text(
                        'ギフトコード入力',
                        'Gift Code',
                      ),
                      accentColor: _homeCyan,
                      onPressed: () => unawaited(
                        _showAdRemovalGiftCodeDialog(dialogContext),
                      ),
                    ),
                  ],
                  if (AppReviewConfig.hasPrivacyPolicy) ...[
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: AppSettings.instance.text(
                        'プライバシーポリシー',
                        'Privacy Policy',
                      ),
                      accentColor: _homeCyan,
                      onPressed: () => unawaited(
                        _openExternalUri(AppReviewConfig.privacyPolicyUrl),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildCyberDialogButton(
                    label: AppSettings.instance.text('閉じる', 'Close'),
                    accentColor: Colors.white70,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAudioSettingsDialog(
    BuildContext parentContext, {
    required double initialMusicVolume,
    required double initialSfxVolume,
    required Future<void> Function(double value) onMusicChanged,
    required Future<void> Function(double value) onSfxChanged,
  }) async {
    double musicVolume = initialMusicVolume;
    double sfxVolume = initialSfxVolume;

    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateLocalMusic(double value) async {
              setDialogState(() {
                musicVolume = value;
              });
              await onMusicChanged(value);
            }

            Future<void> updateLocalSfx(double value) async {
              setDialogState(() {
                sfxVolume = value;
              });
              await onSfxChanged(value);
            }

            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: '音量設定',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSettingsSlider(
                    label: '音楽',
                    value: musicVolume,
                    onChanged: (value) => unawaited(updateLocalMusic(value)),
                  ),
                  const SizedBox(height: 10),
                  _buildSettingsSlider(
                    label: '効果音',
                    value: sfxVolume,
                    onChanged: (value) => unawaited(updateLocalSfx(value)),
                  ),
                  const SizedBox(height: 16),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: Colors.white70,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showControlSettingsDialog(
    BuildContext parentContext, {
    required ControlLayoutPreset initialLayout,
    required Future<void> Function(ControlLayoutPreset preset) onLayoutChanged,
  }) async {
    var layout = initialLayout;

    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> updateLocalLayout(ControlLayoutPreset preset) async {
              setDialogState(() {
                layout = preset;
              });
              await onLayoutChanged(preset);
            }

            return _buildCyberDialog(
              accentColor: _homeCyan,
              title: '操作設定',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final preset in ControlLayoutPreset.values) ...[
                    _buildControlLayoutOption(
                      preset: preset,
                      selected: preset == layout,
                      onTap: () => unawaited(updateLocalLayout(preset)),
                    ),
                    if (preset != ControlLayoutPreset.values.last)
                      const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 16),
                  _buildCyberDialogButton(
                    label: '閉じる',
                    accentColor: Colors.white70,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showInviteCodeDialog(BuildContext parentContext) async {
    await _playerDataManager.load();
    if (!parentContext.mounted) {
      return;
    }
    final inviteCodeController = TextEditingController();
    var ownCode = '';
    var loadingCode = true;
    var redeeming = false;

    try {
      await showDialog<void>(
        context: parentContext,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> loadCode() async {
                if (!loadingCode && ownCode.isNotEmpty) {
                  return;
                }
                final code = await InviteManager.instance.ensureInviteCode(
                  displayName: _playerDataManager.displayPlayerName,
                  publicId: _playerDataManager.playerId,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                setDialogState(() {
                  ownCode = code;
                  loadingCode = false;
                });
              }

              if (loadingCode) {
                unawaited(loadCode());
              }

              Future<void> redeemCode() async {
                if (redeeming) {
                  return;
                }
                setDialogState(() {
                  redeeming = true;
                });
                final result = await InviteManager.instance.redeemCode(
                  inviteCodeController.text,
                  inviteeName: _playerDataManager.displayPlayerName,
                  inviteePublicId: _playerDataManager.playerId,
                );
                if (dialogContext.mounted) {
                  setDialogState(() {
                    redeeming = false;
                  });
                  Navigator.of(dialogContext).pop();
                }
                if (!mounted) {
                  return;
                }
                await _showInviteRedeemResult(
                  this.context,
                  result,
                );
              }

              Future<void> copyOwnCode() async {
                if (ownCode.isEmpty || loadingCode) {
                  return;
                }
                await Clipboard.setData(ClipboardData(text: ownCode));
                if (!mounted) {
                  return;
                }
                await _showAlert(
                  this.context,
                  '招待コード',
                  '友達招待コードをコピーしました。',
                );
              }

              return _buildCyberDialog(
                accentColor: _homeCyan,
                title: '招待コード',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInviteRewardDescription(
                      fontSize: 12,
                      firstLine: '24時間以内に3人まで使える友達招待コードです。',
                      secondLine: '友達がコードを使って1回プレイすると、友達とあなたに',
                      suffix: 'が届きます。',
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _homeCyanBorder),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            '友達招待コード',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            loadingCode
                                ? '発行中...'
                                : ownCode.isEmpty
                                    ? '取得できませんでした'
                                    : ownCode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _homeCyan,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: 'コピー',
                      accentColor: _homeCyan,
                      onPressed: ownCode.isEmpty || loadingCode
                          ? () {}
                          : () => unawaited(copyOwnCode()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: inviteCodeController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '友達の招待コード',
                        labelStyle: TextStyle(color: Colors.white70),
                        helperText: '新しく始めたプレイヤーのみ、1回だけ入力できます',
                        helperStyle: TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _homeCyanBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: _homeCyanBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildCyberDialogButton(
                      label: redeeming ? '確認中...' : 'コードを使う',
                      accentColor: _homeCyan,
                      onPressed:
                          redeeming ? () {} : () => unawaited(redeemCode()),
                    ),
                    const SizedBox(height: 12),
                    _buildCyberDialogButton(
                      label: '閉じる',
                      accentColor: Colors.white54,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      inviteCodeController.dispose();
    }
  }

  String _inviteRedeemTitle(InviteRedeemStatus status) {
    return switch (status) {
      InviteRedeemStatus.accepted => '招待コード',
      InviteRedeemStatus.alreadyUsed => '招待コード',
      InviteRedeemStatus.notEligible => '招待コード',
      InviteRedeemStatus.expired => 'コードエラー',
      InviteRedeemStatus.codeUsed => 'コードエラー',
      InviteRedeemStatus.ownCode => 'コードエラー',
      InviteRedeemStatus.notFound => 'コードエラー',
      InviteRedeemStatus.disabled => 'コードエラー',
      InviteRedeemStatus.invalid => 'コードエラー',
      InviteRedeemStatus.failed => '通信エラー',
    };
  }

  String _inviteRedeemMessage(InviteRedeemResult result) {
    return switch (result.status) {
      InviteRedeemStatus.accepted =>
        '${result.inviterName}さんの招待コードを登録しました。\nいずれかのゲームモードを1回プレイすると、友達とあなたに報酬が届きます。',
      InviteRedeemStatus.alreadyUsed => '招待コードは1アカウントにつき1回だけ使用できます。',
      InviteRedeemStatus.notEligible =>
        '招待コード特典は、招待コード機能の開始後に新しく始めたプレイヤーが対象です。',
      InviteRedeemStatus.expired => 'この友達招待コードは有効期限が切れています。',
      InviteRedeemStatus.codeUsed => 'この友達招待コードはすでに使用されています。',
      InviteRedeemStatus.ownCode => '自分の招待コードは使用できません。',
      InviteRedeemStatus.notFound => 'この招待コードは見つかりませんでした。',
      InviteRedeemStatus.disabled => 'この招待コードは現在使用できません。',
      InviteRedeemStatus.invalid => '招待コードの形式が正しくありません。',
      InviteRedeemStatus.failed => '招待コードを確認できませんでした。通信状況を確認してもう一度お試しください。',
    };
  }

  Future<void> _showInviteRedeemResult(
    BuildContext context,
    InviteRedeemResult result,
  ) {
    if (result.status != InviteRedeemStatus.accepted) {
      return _showAlert(
        context,
        _inviteRedeemTitle(result.status),
        _inviteRedeemMessage(result),
      );
    }
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _buildCyberDialog(
          accentColor: _homeCyan,
          title: '招待コード',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${result.inviterName}さんの招待コードを登録しました。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildInviteRewardDescription(
                fontSize: 13,
                firstLine: 'いずれかのゲームモードを1回プレイすると、',
                secondLine: '友達とあなたに',
                suffix: 'が届きます。',
              ),
              const SizedBox(height: 20),
              _buildCyberDialogButton(
                label: 'OK',
                accentColor: _homeCyan,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShareNoticeMessage() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'リザルト画面から、対戦結果やエンドレスのスコアを画像でシェアできるようになりました。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _buildInviteRewardDescription(
          fontSize: 13,
          firstLine: 'シェア画像内の招待コードを友達がインストール時に入力すると、',
          secondLine: '友達とあなたに',
          suffix: 'が届きます。',
        ),
        const SizedBox(height: 12),
        const Text(
          'じゃんじゃん結果を共有して、ライバルに挑戦状を送りましょう！',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInviteRewardDescription({
    required double fontSize,
    required String firstLine,
    required String secondLine,
    required String suffix,
  }) {
    final textStyle = TextStyle(
      color: Colors.white70,
      fontSize: fontSize,
      height: 1.45,
      fontWeight: FontWeight.w700,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          firstLine,
          textAlign: TextAlign.center,
          style: textStyle,
        ),
        const SizedBox(height: 3),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 3,
          children: [
            Text(secondLine, style: textStyle),
            _buildCoinAmount(
              InviteManager.rewardCoins,
              iconSize: fontSize + 4,
              fontSize: fontSize + 2,
              fontWeight: FontWeight.w900,
            ),
            Text(suffix, style: textStyle),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${(value * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Slider(
            value: value,
            onChanged: onChanged,
            activeColor: _homeCyan,
          ),
        ],
      ),
    );
  }

  Widget _buildControlLayoutOption({
    required ControlLayoutPreset preset,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final icons = switch (preset) {
      ControlLayoutPreset.rotateMoveMoveRotate => const [
          Icons.rotate_left,
          Icons.arrow_left,
          Icons.arrow_right,
          Icons.rotate_right,
        ],
      ControlLayoutPreset.moveMoveRotateRotate => const [
          Icons.arrow_left,
          Icons.arrow_right,
          Icons.rotate_left,
          Icons.rotate_right,
        ],
      ControlLayoutPreset.rotateRotateMoveMove => const [
          Icons.rotate_left,
          Icons.rotate_right,
          Icons.arrow_left,
          Icons.arrow_right,
        ],
      ControlLayoutPreset.moveRotateRotateMove => const [
          Icons.arrow_left,
          Icons.rotate_left,
          Icons.rotate_right,
          Icons.arrow_right,
        ],
    };

    return InkWell(
      onTap: () {
        _playUiTap();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _homeCyan.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _homeCyan : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final icon in icons)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0x1100FFFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _homeCyanBorder,
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: _homeCyan,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (selected)
              const Icon(
                Icons.check_circle,
                color: _homeCyan,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCyberDialog({
    required String title,
    required Widget child,
    required Color accentColor,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF141421),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor == _homeCyan
                ? _homeCyanBorder
                : accentColor.withValues(alpha: 0.78),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: accentColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildCyberDialogButton({
    required String label,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    final effectiveAccentColor =
        label == '閉じる' || label == 'キャンセル' ? _mutedButtonGrey : accentColor;
    return OutlinedButton(
      onPressed: () {
        _playUiTap();
        onPressed();
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: effectiveAccentColor,
        side: BorderSide(
          color: effectiveAccentColor == _homeCyan
              ? _homeCyanBorder
              : effectiveAccentColor.withValues(alpha: 0.75),
          width: 1.4,
        ),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        AppSettings.instance.translate(label),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.6,
        ),
      ),
    );
  }

  Future<void> _showDebugMenu() async {
    if (!_debugControlsEnabled) {
      return;
    }

    await _refreshPlayerEconomy();
    if (!mounted) {
      return;
    }

    final rateController = TextEditingController(text: '$_rating');
    final arenaWinsController =
        TextEditingController(text: '${_arenaManager.currentWins}');
    final arenaLossesController =
        TextEditingController(text: '${_arenaManager.currentLosses}');
    final coinsController = TextEditingController(text: '$_coins');
    final expDeltaController = TextEditingController(text: '1000');
    var arenaActive = _arenaManager.isArenaActive;
    var generatedGiftCode = '';

    int intValue(TextEditingController controller, int fallback) {
      return int.tryParse(controller.text.trim()) ?? fallback;
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> applyDebugValues() async {
                final nextRating = intValue(rateController, _rating);
                final nextCoins = intValue(coinsController, _coins);
                final nextWins =
                    intValue(arenaWinsController, _arenaManager.currentWins);
                final nextLosses = intValue(
                    arenaLossesController, _arenaManager.currentLosses);

                _multiplayerManager.currentRating = nextRating;
                await _playerDataManager.setCurrentRating(nextRating);
                await _playerDataManager.setCoinsForDebug(nextCoins);
                await _playerDataManager.updateMaxArenaWins(nextWins);
                await _arenaManager.setArenaStateForDebug(
                  isActive: arenaActive,
                  wins: nextWins,
                  losses: nextLosses,
                );
                unawaited(_rankingManager.updateMyRating(rating: nextRating));

                if (!mounted) {
                  return;
                }
                setState(() {
                  _rating = nextRating;
                });
                await _refreshPlayerEconomy();
              }

              Future<void> adjustExp(int sign) async {
                final delta = intValue(expDeltaController, 0).abs() * sign;
                await _playerDataManager.adjustExpForDebug(delta);
                await _refreshPlayerEconomy();
              }

              Future<void> toggleAdsRemoved() async {
                final nextValue = !AppSettings.instance.adsRemoved.value;
                await AppSettings.instance.setAdsRemoved(nextValue);
                if (!mounted) {
                  return;
                }
                await _showAlert(
                  this.context,
                  '広告設定',
                  nextValue ? '広告削除を有効にしました。' : '広告表示を再度有効にしました。',
                );
                if (mounted) {
                  setSheetState(() {});
                }
              }

              void generateGiftCode() {
                final code = AppSettings.instance.generateAdRemovalGiftCode();
                setSheetState(() {
                  generatedGiftCode = code;
                });
              }

              return SafeArea(
                child: Container(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F13).withValues(alpha: 0.97),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(
                      color: Colors.purpleAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'デバッグ操作',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildDebugNumberField('レート', rateController),
                        const SizedBox(height: 10),
                        _buildDebugNumberField('所持数', coinsController),
                        const SizedBox(height: 10),
                        if (_adGiftCodeIssuerEnabled) ...[
                          _buildCyberDialogButton(
                            label: '使い切りギフトコード発行',
                            accentColor: Colors.purpleAccent,
                            onPressed: generateGiftCode,
                          ),
                          if (generatedGiftCode.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                _playUiTap();
                                unawaited(
                                  Clipboard.setData(
                                    ClipboardData(text: generatedGiftCode),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.purpleAccent
                                        .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: SelectableText(
                                  generatedGiftCode,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.purpleAccent,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _buildDebugNumberField(
                                'アリーナ 勝利数',
                                arenaWinsController,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDebugNumberField(
                                'アリーナ 敗北数',
                                arenaLossesController,
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: arenaActive,
                          onChanged: (value) {
                            setSheetState(() {
                              arenaActive = value;
                            });
                          },
                          activeThumbColor: _homeCyan,
                          title: const Text(
                            'アリーナ エントリー中',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildCyberDialogButton(
                          label: '値を反映',
                          accentColor: _homeCyan,
                          onPressed: () => unawaited(applyDebugValues()),
                        ),
                        const SizedBox(height: 16),
                        _buildDebugNumberField('EXP 変化量', expDeltaController),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: 'EXP +',
                                accentColor: _endlessGreen,
                                onPressed: () => unawaited(adjustExp(1)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildCyberDialogButton(
                                label: 'EXP -',
                                accentColor: _friendPink,
                                onPressed: () => unawaited(adjustExp(-1)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildCyberDialogButton(
                          label: AppSettings.instance.adsRemoved.value
                              ? '広告を再度つける'
                              : '広告を消す',
                          accentColor: Colors.orangeAccent,
                          onPressed: () => unawaited(toggleAdsRemoved()),
                        ),
                        const SizedBox(height: 12),
                        _buildCyberDialogButton(
                          label: 'ミッション一覧',
                          accentColor: Colors.amberAccent,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_openMissionScreen());
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildCyberDialogButton(
                          label: 'テキストスタンプLv確認',
                          accentColor: Colors.purpleAccent,
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _showStampDebugPreview();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      rateController.dispose();
      arenaWinsController.dispose();
      arenaLossesController.dispose();
      coinsController.dispose();
      expDeltaController.dispose();
    }
  }

  Widget _buildDebugNumberField(
    String label,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white60,
          fontWeight: FontWeight.bold,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _homeCyanBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _homeCyanBorder),
        ),
      ),
    );
  }

  void _showStampDebugPreview() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F13).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border:
                Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              const Text(
                'テキストスタンプ Lv確認',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '各テキストスタンプのLv.1〜Lv.4表示を確認できます。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: GameItemCatalog.commonStamps.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = GameItemCatalog.commonStamps[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.purpleAccent.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildStampLevelPreviewGrid(item),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStampLevelPreviewGrid(GameItem item) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var level = 1; level <= 4; level++)
              _buildStampLevelPreviewCard(
                item: item,
                level: level,
                width: cardWidth,
              ),
          ],
        );
      },
    );
  }

  Widget _buildStampLevelPreviewCard({
    required GameItem item,
    required int level,
    required double width,
  }) {
    return Container(
      width: width,
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            'Lv.$level',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: StampWidget(item: item, level: level),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankedMatchmakingEstimate extends StatefulWidget {
  const _RankedMatchmakingEstimate();

  @override
  State<_RankedMatchmakingEstimate> createState() =>
      _RankedMatchmakingEstimateState();
}

class _RankedMatchmakingEstimateState
    extends State<_RankedMatchmakingEstimate> {
  static const int _visibleAfterSeconds = 5;
  static const int _estimatedBotMatchSeconds = 15;

  late final DateTime _startedAt;
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) {
      return;
    }
    setState(() {
      _elapsedSeconds = DateTime.now().difference(_startedAt).inSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_elapsedSeconds < _visibleAfterSeconds) {
      return const SizedBox(height: 0);
    }

    final remaining =
        (_estimatedBotMatchSeconds - _elapsedSeconds).clamp(0, 10);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        'マッチングまで推定$remaining秒',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _rankedPurpleText.withValues(alpha: 0.92),
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _RankedMatchmakingHint extends StatefulWidget {
  const _RankedMatchmakingHint();

  @override
  State<_RankedMatchmakingHint> createState() => _RankedMatchmakingHintState();
}

class _RankedMatchmakingHintState extends State<_RankedMatchmakingHint> {
  static const List<String> _hints = [
    'ネクストボールを見ると、次の一手が少しだけ未来になります。',
    'ヘキサゴンを狙いすぎると、盤面が小声で止めてきます。',
    '序盤は低く、終盤は冷静に。だいたいこれで助かります。',
    '相手の盤面が高い時は、攻めるチャンスです。',
    '自分の盤面が高い時は、まず深呼吸。次に消しましょう。',
    'ピラミッドは作りやすく、頼れるフォーメーションです。',
    'ストレートは素早く妨害を送りたい時に有効です。',
    '端に積みすぎると、あとで端に泣かされます。',
    '大技が見えない時は、小さな消去で流れを作りましょう。',
    '相手のネクストを見ると、攻撃タイミングを読みやすくなります。',
    'ハードドロップは速いですが、置きミスも速いです。',
    '迷ったら中央を整えると、次の一手が楽になります。',
    '妨害ボールも、使い方次第では味方になります。',
    '勝っている時ほど、安全確認が大事です。',
    '負けている時でも、1回のフォーメーションでひっくり返せます。',
    'レートは大事。でもまずは目の前の3個です。',
    '連勝中の油断は、だいたい次の試合で回収されます。',
    '盤面が荒れてきたら、大技よりも整地を優先しましょう。',
    'たまには守りの一手が、一番攻撃的な一手になります。',
    'マッチング中は指を温めておきましょう。心も少しだけ。',
    'レート差があっても、盤面は平等です。',
    '焦って置いた1手は、未来の自分への宿題になります。',
    '今日の勝利数ランキング、上の方はだいたい本気です。',
    '調子が悪い時は、ボールのせいにしてから切り替えましょう。',
    '負けても次があります。レートは逃げますが、また捕まえられます。',
  ];

  late int _index;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _index = DateTime.now().millisecondsSinceEpoch % _hints.length;
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _nextHint());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _nextHint() {
    if (!mounted) {
      return;
    }
    setState(() {
      _index = (_index + 1) % _hints.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _nextHint,
      child: Container(
        width: double.infinity,
        height: 92,
        decoration: BoxDecoration(
          color: _rankedPurple.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _rankedPurple.withValues(alpha: 0.28),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 14,
              top: 9,
              child: Text(
                'ヒント',
                style: TextStyle(
                  color: _rankedPurple.withValues(alpha: 0.95),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Icon(
                Icons.play_arrow_rounded,
                size: 26,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
            Positioned.fill(
              left: 18,
              right: 42,
              top: 28,
              bottom: 12,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Center(
                  key: ValueKey(_index),
                  child: Text(
                    _hints[_index],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButtonBorderOverlayPainter extends CustomPainter {
  static const double _strokeWidth = 2.4;
  static const double _arcRadius = 76.3;
  static const double _arcGap = 0.065;

  final List<Color> _colors = [
    _endlessGreen,
    _friendPink,
    _computerYellow,
    const Color(0xFF8B96A3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final arcRect = Rect.fromCircle(center: center, radius: _arcRadius);
    final arcs = [
      (start: math.pi + _arcGap, color: _colors[0]),
      (start: -math.pi / 2 + _arcGap, color: _colors[1]),
      (start: math.pi / 2 + _arcGap, color: _colors[2]),
      (start: _arcGap, color: _colors[3]),
    ];

    for (final arc in arcs) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = _strokeWidth
        ..color = arc.color.withValues(alpha: 0.58);
      canvas.drawArc(
        arcRect,
        arc.start,
        math.pi / 2 - (_arcGap * 2),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ModeButtonBorderOverlayPainter oldDelegate) {
    return true;
  }
}
