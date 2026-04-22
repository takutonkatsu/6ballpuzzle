import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_options.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeMobileAds();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      home: const HomeScreen(),
    );
  }
}
