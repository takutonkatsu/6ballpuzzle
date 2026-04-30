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
import 'game/components/ball_component.dart';
import 'game/game_models.dart';
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
    await Future.wait([
      _progressController.forward(from: 0),
      Future<void>.delayed(const Duration(milliseconds: 1800)),
    ]);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const HomeScreen(),
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 138,
                height: 138,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.4),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(alpha: 0.18),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 20,
                      child: MiniBallWidget(
                        ballColor: BallColor.red,
                        size: 52,
                      ),
                    ),
                    Positioned(
                      left: 15,
                      bottom: 18,
                      child: MiniBallWidget(
                        ballColor: BallColor.blue,
                        size: 52,
                      ),
                    ),
                    Positioned(
                      right: 15,
                      bottom: 18,
                      child: MiniBallWidget(
                        ballColor: BallColor.green,
                        size: 52,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'ヘキサゴン',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '6ボール対戦パズル',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '2026©Takutonkatsu',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'LOADING',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return LinearProgressIndicator(
                      value: _progressController.value,
                      minHeight: 12,
                      backgroundColor: Colors.white12,
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
      ),
    );
  }
}
