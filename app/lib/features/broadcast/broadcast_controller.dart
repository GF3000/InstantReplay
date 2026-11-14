import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:replay_capture_android/replay_capture_android.dart' show BroadcastConfig, BroadcastState, BroadcastStatus;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../camera/capture_layer.dart';
import 'broadcast_host.dart';
import 'mic_level.dart';

/// The YouTube stream on the Camera (SPEC §12.1): where to send it (kept in preferences, the key
/// never leaves this phone) and the latest state from the plugin.
class BroadcastController {
  BroadcastController({required this._prefs, required this.capture})
      : micLevel = MicLevelPoller(
          read: capture.broadcastMicLevel,
          // Before going live the Camera measures the microphone only while a meter shows it.
          onRunning: (on) => unawaited(capture.broadcastMicPreview(on).catchError((Object _) {})),
        ) {
    _syncMicLevel();
    _subs
      ..add(capture.broadcast.listen((s) => _onNative(s, significant: true)))
      ..add(capture.stats.listen((s) {
        if (s.broadcast case final b?) _onNative(b, significant: b.state != _native?.state);
      }));
  }

  static const serverKey = 'broadcast.server';
  static const streamKeyKey = 'broadcast.key';
  static const kbpsKey = 'broadcast.kbps';
  static const audioKey = 'broadcast.audio';
  static const replayScoreboardKey = 'broadcast.replayScoreboard';

  final SharedPreferences _prefs;
  final CaptureLayer capture;
  final _subs = <StreamSubscription<Object?>>[];
  final _changes = StreamController<BroadcastInfo>.broadcast();
  final _stateChanges = StreamController<void>.broadcast();
  BroadcastStatus? _native;

  /// The stream microphone's level in dBFS (muted or not), polled only while something listens
  /// and either a stream runs or, before going live, the microphone is set on (measured with the
  /// permission already granted); null without an open microphone.
  final MicLevelPoller micLevel;

  String get server => _prefs.getString(serverKey) ?? BroadcastInfo.defaultServer;

  String? get _key => switch (_prefs.getString(streamKeyKey)?.trim()) {
        final k? when k.isNotEmpty => k,
        _ => null,
      };

  int get targetKbps => clampKbps(_prefs.getInt(kbpsKey) ?? BroadcastInfo.defaultKbps);

  bool get audio => _prefs.getBool(audioKey) ?? true;

  /// Scoreboard over replays on air (SPEC §12.6); off by default.
  bool get replayScoreboard => _prefs.getBool(replayScoreboardKey) ?? false;

  bool get configured => _key != null;

  /// What viewers see: the configuration (with only a hint of the key) and the latest native state.
  BroadcastInfo get info {
    final n = _native;
    return BroadcastInfo(
      state: n == null ? BroadcastStreamState.idle : BroadcastStreamState.values.byName(n.state.name),
      configured: configured,
      server: server,
      keyHint: keyHint(_key),
      targetKbps: targetKbps,
      // While live: whether the mic really is on air (it may lack permission).
      audio: n != null && _live(n) ? n.audio : audio,
      replayScoreboard: replayScoreboard,
      bitrateKbps: n?.bitrateKbps,
      uptimeMs: n?.uptimeMs,
      message: n?.message,
    );
  }

  /// Every change, including the bitrate and uptime that come with each stats tick.
  Stream<BroadcastInfo> get changes => _changes.stream;

  /// Configuration and stream state changes only.
  Stream<void> get stateChanges => _stateChanges.stream;

  Future<void> configure({
    required String server,
    String? key,
    required int targetKbps,
    required bool audio,
    bool? replayScoreboard,
  }) async {
    if (replayScoreboard != null) await _prefs.setBool(replayScoreboardKey, replayScoreboard);
    final s = server.trim();
    await _prefs.setString(serverKey, s.isEmpty ? BroadcastInfo.defaultServer : s);
    final k = key?.trim();
    if (k != null && k.isNotEmpty) await _prefs.setString(streamKeyKey, k);
    await _prefs.setInt(kbpsKey, clampKbps(targetKbps));
    final audioChanged = audio != this.audio;
    await _prefs.setBool(audioKey, audio);
    _syncMicLevel();
    if (audioChanged) await _applyAudioLive(audio);
    _emit(significant: true);
  }

  /// The microphone button (SPEC §12.7): on or off at once, also on air, and remembered for the
  /// next stream. Returns false when it could not go on air (no microphone permission; asked).
  Future<bool> setAudio(bool on) async {
    await _prefs.setBool(audioKey, on);
    _syncMicLevel();
    final ok = await _applyAudioLive(on);
    _emit(significant: true);
    return ok;
  }

  Future<bool> _applyAudioLive(bool on) async {
    final n = _native;
    if (n == null || !_live(n)) return true;
    var ok = await capture.broadcastSetAudio(on).catchError((Object _) => false);
    if (on && !ok) {
      // The stream started without the mic: ask now; it is open from the next stream on.
      await capture.requestMicPermission().catchError((Object _) => false);
      ok = false;
    }
    try {
      _onNative(await capture.broadcastStatus(), significant: true);
    } catch (_) {
      // The event stream brings it anyway.
    }
    return ok;
  }

  static bool _live(BroadcastStatus n) => n.state != BroadcastState.idle && n.state != BroadcastState.failed;

  /// Goes live. Returns false when the microphone permission was denied: the stream then carries
  /// a silent track. Throws [BroadcastException] `not_configured` or `broadcast_failed`.
  Future<bool> start() async {
    final key = _key;
    if (key == null) throw const BroadcastException('not_configured');
    var withAudio = audio;
    var micOk = true;
    if (withAudio) {
      try {
        micOk = await capture.requestMicPermission();
      } catch (_) {
        micOk = false;
      }
      withAudio = micOk;
    }
    try {
      final status = await capture.broadcastStart(
        BroadcastConfig(url: streamUrl(server, key), targetKbps: targetKbps, audio: withAudio),
      );
      _onNative(status, significant: true);
    } on PlatformException catch (e) {
      throw BroadcastException(e.code == 'not_broadcast_mode' ? e.code : 'broadcast_failed', e.message ?? e.code);
    }
    return micOk;
  }

  Future<void> stop() async {
    try {
      await capture.broadcastStop();
    } on PlatformException catch (e) {
      throw BroadcastException('broadcast_failed', e.message ?? e.code);
    }
    try {
      _onNative(await capture.broadcastStatus(), significant: true);
    } catch (_) {
      // The event stream brings it anyway.
    }
  }

  void _onNative(BroadcastStatus status, {required bool significant}) {
    _native = status;
    _syncMicLevel();
    _emit(significant: significant);
  }

  /// On air the stream's mic (muted or not); before going live only a mic set on is measured.
  void _syncMicLevel() {
    final n = _native;
    micLevel.active = (n != null && _live(n)) || audio;
  }

  void _emit({required bool significant}) {
    if (_changes.isClosed) return;
    _changes.add(info);
    if (significant) _stateChanges.add(null);
  }

  void dispose() {
    micLevel.dispose();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_changes.close());
    unawaited(_stateChanges.close());
  }

  /// `rtmp://a.rtmp.youtube.com/live2` + `abcd-1234` → `rtmp://a.rtmp.youtube.com/live2/abcd-1234`.
  static String streamUrl(String server, String key) =>
      '${server.trim().replaceFirst(RegExp(r'/+$'), '')}/${key.trim()}';

  /// Last 4 characters of the key, or null without one.
  static String? keyHint(String? key) {
    if (key == null || key.isEmpty) return null;
    return key.length <= 4 ? key : key.substring(key.length - 4);
  }

  static int clampKbps(int kbps) => kbps.clamp(BroadcastInfo.minKbps, BroadcastInfo.maxKbps);
}
