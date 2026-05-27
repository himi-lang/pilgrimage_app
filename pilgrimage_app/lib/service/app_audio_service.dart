import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAudioService {
  AppAudioService._();

  static final AppAudioService instance = AppAudioService._();

  static const String startSoundPath = 'music_dir/bem_start_mobile_mono.wav';
  static const String mainBgmPath = 'music_dir/bgm_main_mobile_mono.wav';
  static const String versusWaitingBgmPath =
      'music_dir/bgm_versus_waiting_mobile_mono.wav';
  static const String versusPlayingBgmPath =
      'music_dir/bgm_versus_playing_mobile_mono.wav';
  static const String tapSfxPath = 'music_dir/SEタップ音.mp3';

  static const double _mainBgmVolume = 0.42;
  static const double _versusWaitingBgmVolume = 0.46;
  static const double _versusPlayingBgmBaseVolume = 0.46;
  static const double _startSoundVolume = 1.0;
  static const double _tapSfxVolume = 0.82;
  static const String _bgmEnabledPrefsKey = 'audio_bgm_enabled';
  static const String _sfxEnabledPrefsKey = 'audio_sfx_enabled';
  static const String _bgmVolumePrefsKey = 'audio_bgm_volume';
  static const String _sfxVolumePrefsKey = 'audio_sfx_volume';
  static const String _versusPlayingBgmVolumePrefsKey =
      'audio_versus_playing_bgm_volume';

  final AudioPlayer _screenBgmPlayer = AudioPlayer(
    playerId: 'screen_bgm_player',
  );
  final AudioPlayer _startSoundPlayer = AudioPlayer(
    playerId: 'start_sound_player',
  );
  final List<AudioPlayer> _tapSfxPlayers = List.generate(
    4,
    (index) => AudioPlayer(playerId: 'tap_sfx_player_$index'),
  );

  String? _currentScreenBgmPath;
  String? _currentStartSoundPath;
  String? _requestedScreenBgmPath;
  bool _startSoundRequested = false;
  double _requestedScreenBgmVolume = 0;
  double _screenBgmVolume = 0;
  double _startSoundCurrentVolume = 0;
  int _screenBgmGeneration = 0;
  int _startSoundGeneration = 0;
  int _tapSfxIndex = 0;
  bool _bgmEnabled = true;
  bool _sfxEnabled = true;
  double _bgmVolume = 1.0;
  double _sfxVolume = 1.0;
  double _versusPlayingBgmVolume = 1.0;
  Future<void>? _initializeFuture;
  DateTime _lastTapSfxAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isBgmEnabled => _bgmEnabled;
  bool get isSfxEnabled => _sfxEnabled;
  double get bgmVolume => _bgmVolume;
  double get sfxVolume => _sfxVolume;
  double get versusPlayingBgmVolume => _versusPlayingBgmVolume;

  double get _versusPlayingBgmRequestedVolume =>
      _versusPlayingBgmBaseVolume * _versusPlayingBgmVolume;

  Future<void> initialize() {
    return _initializeFuture ??= _initialize();
  }

  Future<void> playStartSound() async {
    await initialize();
    _startSoundRequested = true;
    if (!_bgmEnabled) {
      await _stopStartSound(clearRequest: false);
      return;
    }

    final generation = ++_startSoundGeneration;
    _startSoundCurrentVolume = _effectiveBgmVolume(_startSoundVolume);

    try {
      await _startSoundPlayer.stop();
      if (generation != _startSoundGeneration) return;
      await _startSoundPlayer.setReleaseMode(ReleaseMode.loop);
      await _startSoundPlayer.setVolume(_startSoundCurrentVolume);
      await _startSoundPlayer.play(AssetSource(startSoundPath));
      _currentStartSoundPath = startSoundPath;
    } catch (e) {
      debugPrint('[AppAudioService] start sound error: $e');
      _currentStartSoundPath = null;
      _startSoundCurrentVolume = 0;
    }
  }

  Future<void> fadeOutStartSound({
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    _startSoundRequested = false;
    if (_currentStartSoundPath == null) return;

    final generation = ++_startSoundGeneration;
    final startVolume = _startSoundCurrentVolume;
    await _fadeOut(
      duration: duration,
      startVolume: startVolume,
      generation: generation,
      isCurrent: () => generation == _startSoundGeneration,
      setVolume: (volume) async {
        _startSoundCurrentVolume = volume;
        await _startSoundPlayer.setVolume(volume);
      },
      stop: () async {
        if (generation != _startSoundGeneration) return;
        await _stopStartSound(clearRequest: false);
      },
    );
  }

  Future<void> playMainBgm() {
    unawaited(fadeOutStartSound(duration: const Duration(milliseconds: 250)));
    return _playScreenBgm(mainBgmPath, volume: _mainBgmVolume);
  }

  Future<void> playVersusWaitingBgm() {
    return _playScreenBgm(
      versusWaitingBgmPath,
      volume: _versusWaitingBgmVolume,
    );
  }

  Future<void> playVersusPlayingBgm() {
    return _playScreenBgm(
      versusPlayingBgmPath,
      volume: _versusPlayingBgmRequestedVolume,
    );
  }

  Future<void> fadeOutScreenBgm({
    String? onlyIfPath,
    Duration duration = const Duration(milliseconds: 700),
  }) async {
    if (onlyIfPath == null || _requestedScreenBgmPath == onlyIfPath) {
      _requestedScreenBgmPath = null;
      _requestedScreenBgmVolume = 0;
    }
    if (onlyIfPath != null && _currentScreenBgmPath != onlyIfPath) return;
    if (_currentScreenBgmPath == null) return;

    final generation = ++_screenBgmGeneration;
    final startVolume = _screenBgmVolume;
    await _fadeOut(
      duration: duration,
      startVolume: startVolume,
      generation: generation,
      isCurrent: () => generation == _screenBgmGeneration,
      setVolume: (volume) async {
        _screenBgmVolume = volume;
        await _screenBgmPlayer.setVolume(volume);
      },
      stop: () async {
        if (generation != _screenBgmGeneration) return;
        await _stopScreenBgm(clearRequest: false);
      },
    );
  }

  Future<void> playTapSfx() async {
    await initialize();
    if (!_sfxEnabled) return;

    final now = DateTime.now();
    if (now.difference(_lastTapSfxAt) < const Duration(milliseconds: 70)) {
      return;
    }
    _lastTapSfxAt = now;

    final player = _tapSfxPlayers[_tapSfxIndex % _tapSfxPlayers.length];
    _tapSfxIndex += 1;

    try {
      await player.stop();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_effectiveSfxVolume(_tapSfxVolume));
      await player.play(AssetSource(tapSfxPath));
    } catch (e) {
      debugPrint('[AppAudioService] tap sfx error: $e');
    }
  }

  VoidCallback? withTapSfx(VoidCallback? callback) {
    if (callback == null) return null;

    return () {
      unawaited(playTapSfx());
      callback();
    };
  }

  Future<void> setBgmEnabled(bool enabled) async {
    await initialize();
    if (_bgmEnabled == enabled) return;

    _bgmEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bgmEnabledPrefsKey, enabled);

    if (!enabled) {
      await _stopStartSound(clearRequest: false);
      await _stopScreenBgm(clearRequest: false);
      return;
    }

    if (_startSoundRequested) {
      await playStartSound();
      return;
    }

    final path = _requestedScreenBgmPath;
    if (path != null) {
      await _playScreenBgm(path, volume: _requestedScreenBgmVolume);
    }
  }

  Future<void> setSfxEnabled(bool enabled) async {
    await initialize();
    if (_sfxEnabled == enabled) return;

    _sfxEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sfxEnabledPrefsKey, enabled);
  }

  Future<void> setBgmVolume(double value) async {
    await initialize();
    _bgmVolume = _normalizeVolume(value);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bgmVolumePrefsKey, _bgmVolume);

    if (_currentStartSoundPath != null) {
      _startSoundCurrentVolume = _effectiveBgmVolume(_startSoundVolume);
      await _startSoundPlayer.setVolume(_startSoundCurrentVolume);
    }

    if (_currentScreenBgmPath != null) {
      _screenBgmVolume = _effectiveBgmVolume(_requestedScreenBgmVolume);
      await _screenBgmPlayer.setVolume(_screenBgmVolume);
    }
  }

  Future<void> setSfxVolume(double value) async {
    await initialize();
    _sfxVolume = _normalizeVolume(value);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_sfxVolumePrefsKey, _sfxVolume);
  }

  Future<void> setVersusPlayingBgmVolume(double value) async {
    await initialize();
    _versusPlayingBgmVolume = _normalizeVolume(value);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _versusPlayingBgmVolumePrefsKey,
      _versusPlayingBgmVolume,
    );

    if (_requestedScreenBgmPath == versusPlayingBgmPath) {
      _requestedScreenBgmVolume = _versusPlayingBgmRequestedVolume;
    }

    if (_currentScreenBgmPath == versusPlayingBgmPath) {
      _screenBgmVolume = _effectiveBgmVolume(_requestedScreenBgmVolume);
      await _screenBgmPlayer.setVolume(_screenBgmVolume);
    }
  }

  Future<void> _playScreenBgm(String path, {required double volume}) async {
    await initialize();
    _requestedScreenBgmPath = path;
    _requestedScreenBgmVolume = volume;
    if (!_bgmEnabled) {
      await _stopScreenBgm(clearRequest: false);
      return;
    }

    final generation = ++_screenBgmGeneration;

    if (_currentScreenBgmPath == path &&
        _screenBgmPlayer.state == PlayerState.playing) {
      _screenBgmVolume = _effectiveBgmVolume(volume);
      try {
        await _screenBgmPlayer.setVolume(_screenBgmVolume);
      } catch (e) {
        debugPrint('[AppAudioService] bgm volume error: $e');
      }
      return;
    }

    _screenBgmVolume = _effectiveBgmVolume(volume);

    try {
      await _screenBgmPlayer.stop();
      if (generation != _screenBgmGeneration) return;
      await _screenBgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _screenBgmPlayer.setVolume(_screenBgmVolume);
      await _screenBgmPlayer.play(AssetSource(path));
      _currentScreenBgmPath = path;
    } catch (e) {
      debugPrint('[AppAudioService] bgm error ($path): $e');
      _currentScreenBgmPath = null;
      _screenBgmVolume = 0;
    }
  }

  Future<void> _stopStartSound({required bool clearRequest}) async {
    if (clearRequest) {
      _startSoundRequested = false;
    }
    _currentStartSoundPath = null;
    _startSoundCurrentVolume = 0;
    await _startSoundPlayer.stop();
  }

  Future<void> _stopScreenBgm({required bool clearRequest}) async {
    if (clearRequest) {
      _requestedScreenBgmPath = null;
      _requestedScreenBgmVolume = 0;
    }
    _currentScreenBgmPath = null;
    _screenBgmVolume = 0;
    await _screenBgmPlayer.stop();
  }

  Future<void> _initialize() async {
    try {
      AudioLogger.logLevel =
          kDebugMode ? AudioLogLevel.info : AudioLogLevel.error;
      final audioContext =
          AudioContextConfig(
            route: AudioContextConfigRoute.system,
            focus: AudioContextConfigFocus.gain,
            respectSilence: false,
          ).build();

      await AudioPlayer.global.setAudioContext(audioContext);
      await _screenBgmPlayer.setAudioContext(audioContext);
      await _startSoundPlayer.setAudioContext(audioContext);
      await _screenBgmPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _startSoundPlayer.setPlayerMode(PlayerMode.mediaPlayer);

      for (final player in _tapSfxPlayers) {
        await player.setAudioContext(audioContext);
        await player.setPlayerMode(PlayerMode.mediaPlayer);
      }

      final prefs = await SharedPreferences.getInstance();
      _bgmEnabled = prefs.getBool(_bgmEnabledPrefsKey) ?? true;
      _sfxEnabled = prefs.getBool(_sfxEnabledPrefsKey) ?? true;
      _bgmVolume = _normalizeVolume(prefs.getDouble(_bgmVolumePrefsKey) ?? 1.0);
      _sfxVolume = _normalizeVolume(prefs.getDouble(_sfxVolumePrefsKey) ?? 1.0);
      _versusPlayingBgmVolume = _normalizeVolume(
        prefs.getDouble(_versusPlayingBgmVolumePrefsKey) ?? 1.0,
      );

      if (kDebugMode) {
        await _debugCheckAssets();
      }
    } catch (e, stackTrace) {
      debugPrint('[AppAudioService] initialize error: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _debugCheckAssets() async {
    const paths = <String>[
      startSoundPath,
      mainBgmPath,
      versusWaitingBgmPath,
      versusPlayingBgmPath,
      tapSfxPath,
    ];

    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;

      for (final path in paths) {
        final assetPath = 'assets/$path';
        final exists = manifest.containsKey(assetPath);
        debugPrint(
          exists
              ? '[AppAudioService] asset ok: $assetPath'
              : '[AppAudioService] asset missing: $assetPath',
        );
      }
    } catch (e) {
      debugPrint('[AppAudioService] asset manifest check failed: $e');
    }
  }

  Future<void> _fadeOut({
    required Duration duration,
    required double startVolume,
    required int generation,
    required bool Function() isCurrent,
    required Future<void> Function(double volume) setVolume,
    required Future<void> Function() stop,
  }) async {
    if (!isCurrent()) return;

    if (duration <= Duration.zero || startVolume <= 0.01) {
      await stop();
      return;
    }

    const steps = 14;
    final stepDuration = Duration(
      milliseconds:
          (duration.inMilliseconds / steps).round().clamp(1, 1000).toInt(),
    );

    for (var step = 1; step <= steps; step += 1) {
      await Future.delayed(stepDuration);
      if (!isCurrent()) return;

      final nextVolume = startVolume * (1 - step / steps);
      try {
        await setVolume(nextVolume.clamp(0.0, 1.0).toDouble());
      } catch (e) {
        debugPrint('[AppAudioService] fade volume error: $e');
        return;
      }
    }

    if (!isCurrent()) return;
    await stop();
  }

  double _effectiveBgmVolume(double baseVolume) {
    return _normalizeVolume(baseVolume * _bgmVolume);
  }

  double _effectiveSfxVolume(double baseVolume) {
    return _normalizeVolume(baseVolume * _sfxVolume);
  }

  double _normalizeVolume(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }
}
