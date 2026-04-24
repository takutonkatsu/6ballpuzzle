import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class SeamlessBgm {
  SeamlessBgm._();

  static final SeamlessBgm instance = SeamlessBgm._();

  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  Timer? _loopTimer;
  Timer? _fadeTimer;
  String? _assetPath;
  Duration? _trackDuration;
  double _volume = 1;
  bool _usingA = true;
  bool _isPlaying = false;
  int _generation = 0;
  Future<void> _operation = Future<void>.value();

  bool get isPlaying => _isPlaying;

  Future<void> play({
    required String assetPath,
    required Duration duration,
    required double volume,
    bool forceRestart = false,
  }) {
    return _enqueue(
      () => _playNow(
        assetPath: assetPath,
        duration: duration,
        volume: volume,
        forceRestart: forceRestart,
      ),
    );
  }

  Future<void> stop() {
    return _enqueue(_stopNow);
  }

  Future<void> dispose() async {
    await stop();
    await Future.wait([
      _playerA.dispose(),
      _playerB.dispose(),
    ]);
  }

  Future<void> _playNow({
    required String assetPath,
    required Duration duration,
    required double volume,
    required bool forceRestart,
  }) async {
    if (_isPlaying &&
        !forceRestart &&
        _assetPath == assetPath &&
        _trackDuration == duration) {
      return;
    }

    await _stopNow();
    _generation++;
    _assetPath = assetPath;
    _trackDuration = duration;
    _volume = volume;
    _usingA = true;
    _isPlaying = true;

    await _prepare(_playerA, assetPath, volume);
    await _prepare(_playerB, assetPath, 0);
    await _playerA.resume();
    _scheduleNext(_generation);
  }

  Future<void> _stopNow() async {
    _generation++;
    _isPlaying = false;
    _loopTimer?.cancel();
    _fadeTimer?.cancel();
    _loopTimer = null;
    _fadeTimer = null;
    await Future.wait([
      _playerA.stop(),
      _playerB.stop(),
    ]);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.catchError((Object _) {}).then((_) => action());
    _operation = next.catchError((Object _) {});
    return next;
  }

  Future<void> _prepare(
    AudioPlayer player,
    String assetPath,
    double volume,
  ) async {
    await player.stop();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(volume);
    await player.setSource(AssetSource(assetPath));
  }

  void _scheduleNext(int generation) {
    final duration = _trackDuration;
    final assetPath = _assetPath;
    if (!_isPlaying || duration == null || assetPath == null) {
      return;
    }

    const overlap = Duration(milliseconds: 180);
    final wait = duration > overlap ? duration - overlap : duration;
    _loopTimer?.cancel();
    _loopTimer = Timer(wait, () {
      if (!_isPlaying || generation != _generation) {
        return;
      }
      unawaited(_crossfadeToNext(generation));
    });
  }

  Future<void> _crossfadeToNext(int generation) async {
    final assetPath = _assetPath;
    if (!_isPlaying || assetPath == null || generation != _generation) {
      return;
    }

    final current = _usingA ? _playerA : _playerB;
    final next = _usingA ? _playerB : _playerA;
    _usingA = !_usingA;

    await next.setVolume(0);
    await next.seek(Duration.zero);
    await next.resume();

    const steps = 9;
    const stepDuration = Duration(milliseconds: 20);
    var step = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      if (!_isPlaying || generation != _generation) {
        timer.cancel();
        return;
      }

      step++;
      final t = step / steps;
      unawaited(current.setVolume(_volume * (1 - t)));
      unawaited(next.setVolume(_volume * t));

      if (step >= steps) {
        timer.cancel();
        unawaited(current.stop());
        unawaited(_prepare(current, assetPath, 0));
        _scheduleNext(generation);
      }
    });
  }
}
