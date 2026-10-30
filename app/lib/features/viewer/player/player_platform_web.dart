import 'dart:js_interop';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'frame_timeline.dart';
import 'player_platform.dart';

PlayerPlatform createPlayerPlatform(VideoPlayerController player) => _WebPlayerPlatform(player);

/// Web: `<video>` shows the frame containing `currentTime`, `requestVideoFrameCallback` says which
/// frame was composited, and a hidden looping video keeps the screen on (SPEC §6).
class _WebPlayerPlatform implements PlayerPlatform {
  _WebPlayerPlatform(this.player);

  final VideoPlayerController player;

  web.HTMLVideoElement? _video;
  int? _frameCallback;

  /// `mediaTime` of the last composited frame, in seconds.
  double? _shown;

  web.WakeLockSentinel? _wakeLock;
  web.HTMLVideoElement? _keepAwakeVideo;
  bool _awake = false;
  bool _disposed = false;

  @override
  SeekRule get seekRule => SeekRule.containing;

  @override
  Future<FrameTimeline?> loadTimeline() async {
    try {
      final response = await web.window.fetch(player.dataSource.toJS).toDart;
      final buffer = await response.arrayBuffer().toDart;
      return parseTimeline(buffer.toDart.asUint8List());
    } on Object {
      return null;
    }
  }

  @override
  Future<Duration?> shownFrameTime() async {
    _watchFrames();
    final shown = _shown;
    // 1 ms in, so float rounding of mediaTime can't land on the end of the previous frame.
    if (shown != null) return Duration(microseconds: (shown * 1e6).round() + 1000);
    return player.position;
  }

  /// video_player_web's element: id `videoElement-<playerId>`, with the clip as its `src`. It is in
  /// the DOM once the platform view is on screen.
  void _watchFrames() {
    if (_video != null || _disposed) return;
    final candidates = web.document.querySelectorAll('video[id^="videoElement-"]');
    for (var i = 0; i < candidates.length; i++) {
      final video = candidates.item(i);
      if (video != null &&
          video.isA<web.HTMLVideoElement>() &&
          (video as web.HTMLVideoElement).src == player.dataSource) {
        _video = video;
        _requestFrame();
        return;
      }
    }
  }

  void _requestFrame() {
    _frameCallback = _video!.requestVideoFrameCallback(
      (JSAny _, _FrameMetadata metadata) {
        if (_disposed) return;
        _shown = metadata.mediaTime;
        _requestFrame();
      }.toJS,
    );
  }

  @override
  void keepAwake(bool on) {
    _watchFrames();
    if (on == _awake || _disposed) return;
    _awake = on;
    if (on) {
      _acquire();
    } else {
      _wakeLock?.release();
      _wakeLock = null;
      _keepAwakeVideo?.pause();
    }
  }

  /// Wake Lock needs a secure context, which the Camera's plain-HTTP server isn't; otherwise a
  /// muted, nearly invisible copy of the clip plays in a loop, which browsers treat as media
  /// playback and keep the screen on for.
  Future<void> _acquire() async {
    if (web.window.isSecureContext) {
      try {
        final lock = await web.window.navigator.wakeLock.request('screen').toDart;
        if (_awake && !_disposed) {
          _wakeLock = lock;
        } else {
          lock.release();
        }
        return;
      } on Object {
        // Fall through to the video.
      }
    }
    final video = _keepAwakeVideo ??= _hiddenVideo();
    try {
      await video.play().toDart;
      if (!_awake || _disposed) video.pause();
    } on Object {
      // Best effort: the screen may still sleep.
    }
  }

  web.HTMLVideoElement _hiddenVideo() {
    final video = web.HTMLVideoElement()
      ..src = player.dataSource
      ..muted = true
      ..loop = true
      ..playsInline = true;
    video.style
      ..position = 'fixed'
      ..right = '0'
      ..bottom = '0'
      ..width = '2px'
      ..height = '2px'
      ..opacity = '0.01'
      ..pointerEvents = 'none';
    web.document.body?.append(video);
    return video;
  }

  @override
  void dispose() {
    _disposed = true;
    final callback = _frameCallback;
    if (callback != null) _video?.cancelVideoFrameCallback(callback);
    _wakeLock?.release();
    final video = _keepAwakeVideo;
    if (video != null) {
      video.pause();
      video.removeAttribute('src');
      video.load();
      video.remove();
    }
  }
}

extension type _FrameMetadata._(JSObject _) implements JSObject {
  external double get mediaTime;
}
