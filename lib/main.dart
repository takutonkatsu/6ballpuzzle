import 'dart:async' show runZonedGuarded, unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'app_maintenance_manager.dart';
import 'app_update_manager.dart';
import 'app_version.dart';
import 'auth/auth_manager.dart';
import 'data/player_data_manager.dart';
import 'firebase_database_provider.dart';
import 'firebase_options_dev.dart' as firebase_dev;
import 'firebase_options_prod.dart' as firebase_prod;
import 'moderation/moderation_manager.dart';
import 'network/multiplayer_manager.dart';
import 'network/ranking_manager.dart';
import 'network/realtime_connection_guard.dart';
import 'purchases/ad_removal_purchase_manager.dart';
import 'ui/game_screen.dart';
import 'ui/home_screen.dart';
import 'ui/theme/game_theme_colors.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Flutter error during app runtime: ${details.exception}');
        if (details.stack != null) {
          debugPrintStack(stackTrace: details.stack);
        }
      };
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]).catchError((Object error, StackTrace stackTrace) {
          debugPrint('Orientation setup failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }),
      );
      runApp(const MyApp());
    },
    (error, stackTrace) {
      debugPrint('Uncaught app error: $error');
      debugPrintStack(stackTrace: stackTrace);
    },
  );
}

Future<void> _initializeEssentialServices() async {
  const isReleaseBuild = bool.fromEnvironment('dart.vm.product');
  const flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: isReleaseBuild ? 'prod' : 'dev',
  );
  const requestedProdFlavor = flavor == 'prod';
  const enableAppCheck =
      bool.fromEnvironment('ENABLE_APP_CHECK', defaultValue: false);
  try {
    final firebaseOptions = requestedProdFlavor
        ? firebase_prod.DefaultFirebaseOptions.currentPlatform
        : firebase_dev.DefaultFirebaseOptions.currentPlatform;
    if (firebaseOptions.databaseURL == null ||
        firebaseOptions.databaseURL!.isEmpty) {
      throw StateError('Firebase Realtime Database URL is not configured.');
    }
    final activeApp = await _initializeFirebaseApp(
      options: firebaseOptions,
      flavor: flavor,
    );
    AppFirebaseDatabase.useApp(activeApp);
    final runtimeIsProd = activeApp.options.projectId ==
        firebase_prod.DefaultFirebaseOptions.currentPlatform.projectId;
    if (activeApp.options.projectId != firebaseOptions.projectId) {
      debugPrint(
        'Firebase project mismatch detected. '
        'FLAVOR=$flavor requested ${firebaseOptions.projectId}, '
        'but runtime is using ${activeApp.options.projectId}. '
        'Continuing with the native-configured app.',
      );
    }
    if (enableAppCheck) {
      try {
        await FirebaseAppCheck.instanceFor(app: activeApp).activate(
          providerAndroid: runtimeIsProd
              ? const AndroidPlayIntegrityProvider()
              : const AndroidDebugProvider(),
          providerApple: runtimeIsProd
              ? const AppleAppAttestProvider()
              : const AppleDebugProvider(),
        );
      } catch (error, stackTrace) {
        debugPrint('Firebase App Check activation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    await AuthManager.instance.ensureSignedIn().timeout(
          const Duration(seconds: 4),
        );
  } catch (error, stackTrace) {
    debugPrint('Startup Firebase/Auth initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  try {
    await AppSettings.instance.load();
  } catch (error, stackTrace) {
    debugPrint('App settings load failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _initializePostLaunchServices() async {
  if (AdRemovalPurchaseManager.isSupportedPlatform) {
    unawaited(AdRemovalPurchaseManager.instance.initialize());
  }
  await _configureSharedGameAudio();
  try {
    await FlameAudio.bgm.initialize();
  } catch (error, stackTrace) {
    debugPrint('BGM initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> _configureSharedGameAudio() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  try {
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
      ),
    );
  } on MissingPluginException {
    // 開発中の古いネイティブビルドではプラグイン未登録でも起動を止めない。
  }
}

Future<FirebaseApp> _initializeFirebaseApp({
  required FirebaseOptions options,
  required String flavor,
}) async {
  final useDefaultApp = Platform.isMacOS;
  final appName = useDefaultApp ? null : 'hexagon-$flavor';
  try {
    return await Firebase.initializeApp(
      name: appName,
      options: options,
    );
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') {
      rethrow;
    }
    final existingApp =
        appName == null ? Firebase.app() : Firebase.app(appName);
    if (_sameFirebaseProject(existingApp.options, options)) {
      return existingApp;
    }
    await existingApp.delete();
    return Firebase.initializeApp(
      name: appName,
      options: options,
    );
  }
}

bool _sameFirebaseProject(FirebaseOptions a, FirebaseOptions b) {
  return a.projectId == b.projectId &&
      a.appId == b.appId &&
      a.databaseURL == b.databaseURL;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ヘキサゴン',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const StartupLoadingScreen(),
    );
  }
}

class StartupLoadingScreen extends StatefulWidget {
  const StartupLoadingScreen({super.key});

  @override
  State<StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<StartupLoadingScreen>
    with TickerProviderStateMixin {
  static const Duration _bootstrapTimeout = Duration(seconds: 8);
  static const Duration _connectionStartupWaitTimeout = Duration(seconds: 8);
  static const Duration _nameRegistrationSyncTimeout = Duration(seconds: 4);

  late final AnimationController _progressController;
  late final AnimationController _startPromptController;
  MaintenanceNotice? _maintenanceNotice;
  HomeBootstrapData? _readyBootstrapData;
  String _publicPlayerId = '';
  bool _isRetryingMaintenance = false;
  bool _isReadyToStart = false;
  bool _isStartingAfterTap = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _startPromptController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _boot();
    unawaited(_loadPublicPlayerId());
  }

  Future<void> _loadPublicPlayerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedPlayerId =
          prefs.getString(PlayerDataManager.playerIdPrefsKey) ?? '';
      if (cachedPlayerId.isNotEmpty && mounted) {
        setState(() {
          _publicPlayerId = cachedPlayerId;
        });
      }
      final playerDataManager = PlayerDataManager.instance;
      await playerDataManager.load();
      final loadedPlayerId = playerDataManager.playerId;
      if (loadedPlayerId.isNotEmpty) {
        await prefs.setString(
          PlayerDataManager.playerIdPrefsKey,
          loadedPlayerId,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _publicPlayerId = loadedPlayerId;
      });
    } catch (_) {
      // ロード画面のID表示に失敗しても起動処理は止めない。
    }
  }

  Future<void> _boot() async {
    final minimumDisplayFuture = Future.wait<void>([
      _progressController.forward(from: 0),
      Future<void>.delayed(const Duration(milliseconds: 1800)),
    ]);
    await _initializeEssentialServices().timeout(
      _bootstrapTimeout,
      onTimeout: () {
        debugPrint(
          'Essential services initialization timed out; continuing startup.',
        );
      },
    );
    if (!mounted) {
      return;
    }

    await _waitForRealtimeDatabaseConnection();
    if (!mounted) {
      return;
    }

    final maintenanceNotice =
        await AppMaintenanceManager.fetchGlobalMaintenance();
    if (!mounted) {
      return;
    }
    if (maintenanceNotice.enabled) {
      setState(() {
        _maintenanceNotice = maintenanceNotice;
      });
      return;
    }

    final updateRequirement = await AppUpdateManager.checkRequirement();
    if (!mounted) {
      return;
    }
    if (updateRequirement.required) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: ForceUpdateScreen(requirement: updateRequirement),
          ),
        ),
      );
      return;
    }

    final bootstrapFuture = prepareHomeBootstrapData().timeout(
      _bootstrapTimeout,
      onTimeout: () {
        debugPrint('Home bootstrap timed out; continuing with local defaults.');
        return _localHomeBootstrapFallback();
      },
    );
    HomeBootstrapData bootstrapData;
    try {
      final results = await Future.wait<Object?>([
        minimumDisplayFuture,
        bootstrapFuture,
      ]);
      bootstrapData = results[1] as HomeBootstrapData;
    } catch (error, stackTrace) {
      debugPrint(
          'Home bootstrap failed; continuing with local defaults: $error');
      debugPrintStack(stackTrace: stackTrace);
      bootstrapData = await _localHomeBootstrapFallback();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _readyBootstrapData = bootstrapData;
      _isReadyToStart = true;
    });
    _startPromptController.repeat(reverse: true);
  }

  Future<void> _startAfterTap() async {
    if (_isStartingAfterTap) {
      return;
    }
    final initialBootstrapData = _readyBootstrapData;
    if (!_isReadyToStart || initialBootstrapData == null) {
      return;
    }
    setState(() {
      _isStartingAfterTap = true;
    });
    _startPromptController.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializePostLaunchServices());
    });
    var bootstrapData = initialBootstrapData;
    if (!AppSettings.instance.onboardingSeen.value) {
      await Navigator.of(context).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: const GameScreen(
              isTutorialMode: true,
              returnToCallerOnExit: true,
            ),
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      final registeredName = await _showStartupNameRegistrationDialog(
        initialName: bootstrapData.playerName,
        rating: bootstrapData.rating,
      );
      if (!mounted) {
        return;
      }
      bootstrapData = HomeBootstrapData(
        playerName: registeredName,
        rating: bootstrapData.rating,
        pendingLevelUpRewardLog: bootstrapData.pendingLevelUpRewardLog,
        abandonedMatchMessage: bootstrapData.abandonedMatchMessage,
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: HomeScreen(bootstrapData: bootstrapData),
        ),
      ),
    );
  }

  Future<void> _retryMaintenanceCheck() async {
    if (_isRetryingMaintenance) {
      return;
    }
    setState(() {
      _isRetryingMaintenance = true;
    });
    final notice = await AppMaintenanceManager.fetchGlobalMaintenance();
    if (!mounted) {
      return;
    }
    if (notice.enabled) {
      setState(() {
        _maintenanceNotice = notice;
        _isRetryingMaintenance = false;
      });
      return;
    }
    setState(() {
      _maintenanceNotice = null;
      _isRetryingMaintenance = false;
    });
    unawaited(_boot());
  }

  Future<HomeBootstrapData> _localHomeBootstrapFallback() async {
    final playerDataManager = PlayerDataManager.instance;
    try {
      await playerDataManager.load();
      return HomeBootstrapData(
        playerName: playerDataManager.playerName,
        rating: playerDataManager.currentRating,
      );
    } catch (_) {
      return const HomeBootstrapData(
        playerName: '',
        rating: 1000,
      );
    }
  }

  Future<void> _waitForRealtimeDatabaseConnection() async {
    final startedAt = DateTime.now();
    while (mounted &&
        DateTime.now().difference(startedAt) < _connectionStartupWaitTimeout) {
      final connected = await RealtimeConnectionGuard.waitForConnected(
        timeout: const Duration(seconds: 2),
      );
      if (connected) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint(
      'Realtime Database connection check timed out; continuing startup.',
    );
  }

  Future<String> _showStartupNameRegistrationDialog({
    required String initialName,
    required int rating,
  }) async {
    final controller = TextEditingController(text: initialName);
    String registeredName = initialName.trim();
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
                setDialogState(() {
                  isSubmitting = true;
                  errorText = null;
                });
                try {
                  final nextName = await ModerationManager.instance
                      .validateAndSanitizePlayerName(controller.text);
                  await _saveAndSyncStartupPlayerName(
                    name: nextName,
                    rating: rating,
                  );
                  registeredName = nextName;
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
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
                child: Dialog(
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
                          color: GameThemeColors.cyanBorder,
                          width: 1.5,
                        )),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '名前を登録',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: GameThemeColors.cyan,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'チュートリアル完了！\n続ける前にプレイヤー名を登録しましょう。',
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
                            counterStyle:
                                const TextStyle(color: Colors.white38),
                            labelStyle: const TextStyle(color: Colors.white70),
                            errorText: errorText,
                            enabledBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: GameThemeColors.cyanBorder,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: GameThemeColors.cyanBorder),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              if (isSubmitting) {
                                return;
                              }
                              unawaited(submit());
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: GameThemeColors.cyan,
                              side: const BorderSide(
                                color: GameThemeColors.cyanBorder,
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                                horizontal: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              isSubmitting ? '登録中...' : '登録',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
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
      controller.dispose();
    }
    return registeredName;
  }

  Future<void> _saveAndSyncStartupPlayerName({
    required String name,
    required int rating,
  }) async {
    final playerDataManager = PlayerDataManager.instance;
    final multiplayerManager = MultiplayerManager.instance;
    final trimmed = name.trim();
    await playerDataManager.setPlayerName(trimmed);
    multiplayerManager.setPlayerName(trimmed);
    unawaited(_syncStartupPlayerNameOnline(rating: rating));
  }

  Future<void> _syncStartupPlayerNameOnline({
    required int rating,
  }) async {
    final playerDataManager = PlayerDataManager.instance;
    final multiplayerManager = MultiplayerManager.instance;
    final rankingManager = RankingManager.instance;
    try {
      await multiplayerManager
          .updateUserName(playerDataManager.playerName)
          .timeout(_nameRegistrationSyncTimeout);
    } catch (_) {
      // 名前はローカルに保存済みなので、オンライン同期の遅延で登録画面を止めない。
    }
    try {
      await rankingManager
          .syncSeasonStateForCurrentPlayer()
          .timeout(_nameRegistrationSyncTimeout);
      await playerDataManager.load().timeout(_nameRegistrationSyncTimeout);
      await rankingManager
          .updateMyRating(
            rating: playerDataManager.currentRating,
            displayName: playerDataManager.displayPlayerName,
          )
          .timeout(_nameRegistrationSyncTimeout);
    } catch (_) {
      // ランキング同期の権限/通信失敗で初回名前登録を止めない。
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _startPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maintenanceNotice = _maintenanceNotice;
    return Scaffold(
      backgroundColor: GameThemeColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isReadyToStart ? () => unawaited(_startAfterTap()) : null,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF08111C),
                Color(0xFF05070D),
              ],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  child: Column(
                    children: [
                      const Spacer(flex: 8),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, child) {
                                final pulse = 0.985 +
                                    math.sin(
                                          _progressController.value *
                                              math.pi *
                                              2,
                                        ) *
                                        0.015;
                                return Transform.scale(
                                  scale: pulse,
                                  child: child,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(36),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    width: 1.1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: GameThemeColors.cyan.withValues(
                                        alpha: 0.14,
                                      ),
                                      blurRadius: 22,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(30),
                                  child: Image.asset(
                                    'assets/images/Hexagon_icon02_1024x1024.png',
                                    width: 168,
                                    height: 168,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'ヘキサゴン',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 7),
                      if (!_isReadyToStart || maintenanceNotice != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: GameThemeColors.surfaceDeep.withValues(
                              alpha: 0.92,
                            ),
                            border: Border.all(
                              color: GameThemeColors.cyanBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: GameThemeColors.cyan,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    maintenanceNotice == null
                                        ? 'ロード中'
                                        : 'メンテナンス中',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (maintenanceNotice == null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: AnimatedBuilder(
                                    animation: _progressController,
                                    builder: (context, child) {
                                      return LinearProgressIndicator(
                                        value: _progressController.value,
                                        minHeight: 10,
                                        backgroundColor: Colors.white10,
                                        valueColor:
                                            const AlwaysStoppedAnimation(
                                          GameThemeColors.cyan,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else
                                _buildMaintenanceContent(maintenanceNotice),
                            ],
                          ),
                        )
                      else
                        Transform.translate(
                          offset: const Offset(0, -18),
                          child: SizedBox(
                            width: double.infinity,
                            child: AnimatedBuilder(
                              animation: _startPromptController,
                              builder: (context, child) {
                                final opacity = 0.38 +
                                    Curves.easeInOut.transform(
                                          _startPromptController.value,
                                        ) *
                                        0.42;
                                return Opacity(
                                  opacity: opacity,
                                  child: child,
                                );
                              },
                              child: Text(
                                _isStartingAfterTap ? '開始中...' : 'タップでスタート',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: GameThemeColors.cyan,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      const Text(
                        '©︎2026 Takutonkatsu',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 12,
                  child: _StartupVersionLabel(
                    publicPlayerId: _publicPlayerId,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaintenanceContent(MaintenanceNotice notice) {
    final expectedEnd = notice.expectedEndAt;
    final expectedText = expectedEnd == null
        ? null
        : '${expectedEnd.month.toString().padLeft(2, '0')}/'
            '${expectedEnd.day.toString().padLeft(2, '0')} '
            '${expectedEnd.hour.toString().padLeft(2, '0')}:'
            '${expectedEnd.minute.toString().padLeft(2, '0')}ごろ再開予定';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          notice.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          notice.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (expectedText != null) ...[
          const SizedBox(height: 8),
          Text(
            expectedText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GameThemeColors.cyan,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: _isRetryingMaintenance
              ? null
              : () => unawaited(_retryMaintenanceCheck()),
          style: OutlinedButton.styleFrom(
            foregroundColor: GameThemeColors.cyan,
            side: const BorderSide(color: GameThemeColors.cyanBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(_isRetryingMaintenance ? '確認中...' : '再確認'),
        ),
      ],
    );
  }
}

class _StartupVersionLabel extends StatelessWidget {
  const _StartupVersionLabel({
    required this.publicPlayerId,
  });

  final String publicPlayerId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (publicPlayerId.isNotEmpty) ...[
          Text(
            'ID: $publicPlayerId',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
        ],
        const Text(
          'v$appVersionName',
          style: TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.requirement,
  });

  final AppUpdateRequirement requirement;

  Future<void> _openStore() async {
    final url = Uri.tryParse(requirement.storeUrl);
    if (url == null) {
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF111827),
                Color(0xFF161626),
                Color(0xFF080A12),
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: const Color(0xFF141421),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: GameThemeColors.cyanBorder,
                      width: 1.5,
                    )),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.system_update,
                      color: GameThemeColors.cyan,
                      size: 42,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'アップデートが必要です',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      requirement.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '現在: ${requirement.currentVersion} / 必要: ${requirement.minSupportedVersion.isEmpty ? requirement.minSupportedBuild : requirement.minSupportedVersion}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: requirement.storeUrl.isEmpty
                            ? null
                            : () => unawaited(_openStore()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GameThemeColors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'ストアでアップデート',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
