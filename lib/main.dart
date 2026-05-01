import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // 追加
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_settings.dart';
import 'auth/auth_manager.dart';
import 'firebase_options_dev.dart' as firebase_dev;
import 'firebase_options_prod.dart' as firebase_prod;
import 'ui/home_screen.dart';

Future<void> main() async {
  const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
  const isProd = flavor == 'prod';
  const enableAppCheck =
      bool.fromEnvironment('ENABLE_APP_CHECK', defaultValue: isProd);
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await _initializeMobileAds();
  final firebaseOptions = isProd
      ? firebase_prod.DefaultFirebaseOptions.currentPlatform
      : firebase_dev.DefaultFirebaseOptions.currentPlatform;
  if (firebaseOptions.databaseURL == null ||
      firebaseOptions.databaseURL!.isEmpty) {
    throw StateError('Firebase Realtime Database URL is not configured.');
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: firebaseOptions,
    );
  } else {
    final existingApp = Firebase.app();
    if (existingApp.options.projectId != firebaseOptions.projectId) {
      throw StateError(
        'A different Firebase app is already configured for '
        '${existingApp.options.projectId}. Remove bundled '
        'GoogleService-Info.plist files so FLAVOR can select '
        '${firebaseOptions.projectId}.',
      );
    }
  }

  if (enableAppCheck) {
    // App Checkは環境ごとにプロバイダを切り替える。
    await FirebaseAppCheck.instance.activate(
      providerAndroid: isProd
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple:
          isProd ? const AppleAppAttestProvider() : const AppleDebugProvider(),
    );
  }

  await AuthManager.instance.ensureSignedIn();
  await AppSettings.instance.load();
  await FlameAudio.bgm.initialize();
  runApp(const MyApp());
}

Future<void> _initializeMobileAds() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return;
  }

  try {
    await MobileAds.instance.initialize();
  } on MissingPluginException {
    // プラグイン未登録の古いビルドや開発中の起動でアプリ全体を止めない。
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '6-Ball Puzzle',
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _boot();
  }

  Future<void> _boot() async {
    final bootstrapFuture = prepareHomeBootstrapData();
    final minimumDisplayFuture = Future.wait<void>([
      _progressController.forward(from: 0),
      Future<void>.delayed(const Duration(milliseconds: 1800)),
    ]);
    final results = await Future.wait<Object?>([
      minimumDisplayFuture,
      bootstrapFuture,
    ]);
    final bootstrapData = results[1] as HomeBootstrapData;
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

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B12),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF09111C),
              Color(0xFF060A12),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const Spacer(flex: 8),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(34),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.cyanAccent.withValues(alpha: 0.16),
                              blurRadius: 32,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: Image.asset(
                            'assets/images/loading_icon_neon_hex.png',
                            width: 184,
                            height: 184,
                            fit: BoxFit.cover,
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
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: const Color(0xFF0D1826),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.12),
                        blurRadius: 18,
                      ),
                    ],
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
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'ロード中',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: _progressController.value,
                              minHeight: 10,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.cyanAccent,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '2026 Takutonkatsu',
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
        ),
      ),
    );
  }
}
