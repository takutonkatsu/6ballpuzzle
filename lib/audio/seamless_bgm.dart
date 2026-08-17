import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class SeamlessBgm {
  SeamlessBgm._();

  static final SeamlessBgm instance = SeamlessBgm._();
  static const Duration _homeLoopLeadTime = Duration(milliseconds: 140);
  static const Duration _battleLoopLeadTime = Duration(milliseconds: 140);
  static const Duration _recoveryWatchdogInterval = Duration(seconds: 2);

  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  Timer? _loopTimer;
  Timer? _recoveryWatchdogTimer;
  String? _assetPath;
  Object? _owner;
  Duration? _trackDuration;
  double _baseVolume = 1;
  double _masterVolume = 1;
  bool _usingA = true;
  bool _isPlaying = false;
  int _suspendCount = 0;
  int _generation = 0;
  Future<void> _operation = Future<void>.value();

  bool get isPlaying => _isPlaying;
  bool get isSuspended => _suspendCount > 0;

  Future<void> play({
    required String assetPath,
    required Duration duration,
    required double volume,
    Object? owner,
    bool forceRestart = false,
  }) {
    return _enqueue(
      () => _playNow(
        assetPath: assetPath,
        duration: duration,
        volume: volume,
        owner: owner,
        forceRestart: forceRestart,
      ),
    );
  }

  Future<void> stop({Object? owner}) {
    return _enqueue(() => _stopNow(owner: owner));
  }

  Future<void> suspendForExternalAudio() {
    return _enqueue(_suspendForExternalAudioNow);
  }

  Future<void> resumeFromExternalAudio() {
    return _enqueue(_resumeFromExternalAudioNow);
  }

  Future<void> setMasterVolume(double volume) {
    return _enqueue(() => _setMasterVolumeNow(volume));
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
    required Object? owner,
    required bool forceRestart,
  }) async {
    if (_isPlaying &&
        !forceRestart &&
        _owner == owner &&
        _assetPath == assetPath &&
        _trackDuration == duration) {
      return;
    }

    await _stopNow();
    _generation++;
    _assetPath = assetPath;
    _owner = owner;
    _trackDuration = duration;
    _baseVolume = volume;
    _usingA = true;
    _isPlaying = true;

    await _prepare(_playerA, assetPath, _effectiveVolume);
    await _prepare(_playerB, assetPath, 0);
    if (isSuspended) {
      _startRecoveryWatchdog();
      return;
    }
    await _playerA.resume();
    _scheduleNext(_generation);
    _startRecoveryWatchdog();
  }

  Future<void> _stopNow({Object? owner}) async {
    if (owner != null && _owner != owner) {
      return;
    }
    _generation++;
    _isPlaying = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    _stopRecoveryWatchdog();
    _owner = null;
    _assetPath = null;
    _trackDuration = null;
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

  Future<void> _resetStandby(AudioPlayer player) async {
    await player.pause();
    await player.seek(Duration.zero);
    await player.setVolume(0);
  }

  double get _effectiveVolume => (_baseVolume * _masterVolume).clamp(0.0, 1.0);

  Future<void> _setMasterVolumeNow(double volume) async {
    _masterVolume = volume.clamp(0.0, 1.0);
    if (!_isPlaying) {
      return;
    }
    final current = _usingA ? _playerA : _playerB;
    final next = _usingA ? _playerB : _playerA;
    await Future.wait([
      current.setVolume(_effectiveVolume),
      next.setVolume(0),
    ]);
  }

  Future<void> _suspendForExternalAudioNow() async {
    _suspendCount++;
    if (_suspendCount > 1) {
      return;
    }
    _generation++;
    _loopTimer?.cancel();
    _loopTimer = null;
    if (!_isPlaying) {
      return;
    }
    await Future.wait([
      _playerA.pause(),
      _playerB.pause(),
    ]);
  }

  Future<void> _resumeFromExternalAudioNow() async {
    if (_suspendCount == 0) {
      return;
    }
    _suspendCount--;
    if (_suspendCount > 0 || !_isPlaying) {
      return;
    }
    final assetPath = _assetPath;
    final duration = _trackDuration;
    if (assetPath == null || duration == null) {
      return;
    }

    _generation++;
    _usingA = true;
    await _prepare(_playerA, assetPath, _effectiveVolume);
    await _prepare(_playerB, assetPath, 0);
    await _playerA.resume();
    _scheduleNext(_generation);
    _startRecoveryWatchdog();
  }

  void _scheduleNext(int generation) {
    final duration = _trackDuration;
    final assetPath = _assetPath;
    if (!_isPlaying || isSuspended || duration == null || assetPath == null) {
      return;
    }

    final loopLeadTime = _loopLeadTimeFor(assetPath);
    _loopTimer?.cancel();
    final wait = duration > loopLeadTime ? duration - loopLeadTime : duration;
    _loopTimer = Timer(wait, () {
      if (!_isPlaying || isSuspended || generation != _generation) {
        return;
      }
      unawaited(_swapToStandby(generation));
    });
  }

  Future<void> _swapToStandby(int generation) async {
    if (!_isPlaying || isSuspended || generation != _generation) {
      return;
    }

    final current = _usingA ? _playerA : _playerB;
    final next = _usingA ? _playerB : _playerA;
    _usingA = !_usingA;

    await next.setVolume(_effectiveVolume);
    await next.seek(Duration.zero);
    await next.resume();
    _scheduleNext(generation);
    await Future<void>.delayed(_loopLeadTimeFor(_assetPath));
    if (!_isPlaying || isSuspended || generation != _generation) {
      return;
    }
    await _resetStandby(current);
  }

  void _startRecoveryWatchdog() {
    _recoveryWatchdogTimer ??= Timer.periodic(
      _recoveryWatchdogInterval,
      (_) => unawaited(
        _enqueue(_recoverInterruptedPlaybackNow),
      ),
    );
  }

  void _stopRecoveryWatchdog() {
    _recoveryWatchdogTimer?.cancel();
    _recoveryWatchdogTimer = null;
  }

  Future<void> _recoverInterruptedPlaybackNow() async {
    final assetPath = _assetPath;
    final duration = _trackDuration;
    if (!_isPlaying || isSuspended || assetPath == null || duration == null) {
      return;
    }

    final current = _usingA ? _playerA : _playerB;
    if (current.state == PlayerState.playing) {
      return;
    }

    _generation++;
    _usingA = true;
    await _prepare(_playerA, assetPath, _effectiveVolume);
    await _prepare(_playerB, assetPath, 0);
    if (!_isPlaying || isSuspended || _assetPath != assetPath) {
      return;
    }
    await _playerA.resume();
    _scheduleNext(_generation);
  }

  Duration _loopLeadTimeFor(String? assetPath) {
    if (assetPath?.contains('/bgm_battle') ?? false) {
      return _battleLoopLeadTime;
    }
    return _homeLoopLeadTime;
  }
}
