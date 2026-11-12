// Marketing screenshots: the real screens, with sample data, inside phone / tablet / laptop
// frames. Not part of `flutter test` (it only runs test/). From app/:
//
//   flutter test marketing
//
// PNGs go to docs/screenshots/. See docs/screenshots/README.md.
import 'dart:typed_data';

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_store.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/live/live_signaling.dart';
import 'package:instant_replay/features/viewer/player/frame_timeline.dart';
import 'package:instant_replay/features/viewer/player/player_platform.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/review_page.dart';
import 'package:instant_replay/features/viewer/viewer_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/harness.dart';

/// Per-language sample content.
class _Copy {
  const _Copy({required this.camera, required this.tags, required this.home, required this.away});

  final String camera;
  final List<String> tags;
  final String home;
  final String away;
}

const _copy = {
  'es': _Copy(camera: 'Pista 1', tags: ['Gol', 'Contraataque', 'Defensa', 'Error'], home: 'LEONES', away: 'HALCONES'),
  'en': _Copy(camera: 'Court 1', tags: ['Goal', 'Fast break', 'Defence', 'Mistake'], home: 'LIONS', away: 'HAWKS'),
};

const _tagColors = [0xFF43A047, 0xFF1E88E5, 0xFFFB8C00, 0xFFE53935];

void main() {
  late List<Uint8List> frames;
  late ReviewFrame review;

  setUpAll(() async {
    await loadFonts();
    frames = [for (var i = 0; i <= 6; i++) await frame(i)];
    review = await reviewFrame();
  });

  for (final lang in _copy.keys) {
    final locale = Locale(lang);
    final copy = _copy[lang]!;

    testWidgets('[$lang] phone: live view, Save and the clip list', (tester) async {
      await pumpFramed(
        tester,
        Devices.android.googlePixel9,
        Orientation.portrait,
        framed(
          Devices.android.googlePixel9,
          Orientation.portrait,
          await _viewer(tester, locale, copy, frames, clips: 6),
        ),
      );
      await capture(tester, 'phone-viewer-$lang', width: 1100);
    });

    testWidgets('[$lang] tablet: broadcast with scoreboard, on YouTube', (tester) async {
      await pumpFramed(
        tester,
        Devices.android.mediumTablet,
        Orientation.landscape,
        framed(
          Devices.android.mediumTablet,
          Orientation.landscape,
          await _viewer(tester, locale, copy, frames, clips: 5, broadcast: true),
        ),
      );
      await capture(tester, 'tablet-broadcast-$lang');
    });

    testWidgets('[$lang] laptop: the Viewer in the browser', (tester) async {
      await pumpFramed(
        tester,
        laptop,
        Orientation.landscape,
        framed(
          laptop,
          Orientation.landscape,
          await _viewer(tester, locale, copy, frames, clips: 8, web: true),
        ),
      );
      await capture(tester, 'laptop-viewer-$lang', width: 2400);
    });

    testWidgets('[$lang] tablet: review with the telestrator', (tester) async {
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _StillVideoPlatform(review.image);
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      final clip = _clip(0, review.image);
      final scope = await _scope(locale, copy, ReviewPage(
        clip: clip,
        playerFactory: _StillVideo.new,
        platformFactory: (_) => _StillPlatform(),
      ));
      await pumpFramed(
        tester,
        Devices.android.mediumTablet,
        Orientation.landscape,
        framed(Devices.android.mediumTablet, Orientation.landscape, scope),
      );
      // A tag on the clip, then draw: an arrow for the run, a circle on the free defender.
      await tester.tap(find.byKey(const ValueKey('review-draw')));
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byKey(const ValueKey('review-canvas')));
      Offset at(Offset f) => canvas.topLeft + Offset(f.dx * canvas.width, f.dy * canvas.height);
      await tester.tap(find.byKey(const ValueKey('draw-tool-arrow')));
      await tester.tap(find.byKey(const ValueKey('draw-thick')));
      await tester.pump();
      final marks = review.marks;
      await _drag(tester, at(marks.arrowFrom), at(marks.arrowTo));
      await tester.tap(find.byKey(const ValueKey('draw-tool-circle')));
      await tester.tap(find.byKey(const ValueKey('draw-color-1')));
      await tester.pump();
      await _drag(tester, at(marks.circleFrom), at(marks.circleTo));
      await settleImages(tester);
      await capture(tester, 'tablet-telestrator-$lang');
    });
  }
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from);
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 10)!);
  }
  await g.up();
  await tester.pumpAndSettle();
}

/// Shared preferences with the sample tags, and the provider scope around [home].
Future<Widget> _scope(Locale locale, _Copy copy, Widget home, {List<Override> overrides = const []}) async {
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    TagsNotifier.storageKey: [
      for (final (i, name) in copy.tags.indexed) '{"id":"t$i","name":"$name","color":${_tagColors[i]}}',
    ].toString(),
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      capabilitiesProvider.overrideWithValue(Capabilities.web),
      ...overrides,
    ],
    child: app(locale, home),
  );
}

Future<Widget> _viewer(
  WidgetTester tester,
  Locale locale,
  _Copy copy,
  List<Uint8List> frames, {
  required int clips,
  bool broadcast = false,
  bool web = false,
}) {
  final list = [for (var i = clips; i >= 1; i--) _clip(i, frames[(i - 1) % (frames.length - 1) + 1])];
  final tags = {
    for (final c in list)
      // Most clips tagged, a couple left plain.
      if (int.parse(c.requestId.substring(1)) % 4 != 0) c.requestId: 't${int.parse(c.requestId.substring(1)) % 4}',
    list.first.requestId: 't0',
  };
  final status = CameraStatus(
    recording: true,
    fps: 30,
    bufferMs: 60000,
    outboxClips: 0,
    thermalStatus: 0,
    batteryPercent: 84,
    plugged: true,
    sessionRecording: broadcast
        ? const SessionRecording(
            state: SessionRecordingState.recording,
            elapsedMs: 52 * 60000 + 31000,
            parts: 1,
            freeBytes: 40000000000,
            lowSpace: false,
          )
        : null,
    scoreboard: broadcast
        ? ScoreboardState(
            home: TeamState(name: copy.home, score: 24, color: 0xFFD32F2F),
            away: TeamState(name: copy.away, score: 21, color: 0xFF1E88E5),
            period: 2,
            periodMs: 30 * 60000,
            clockMs: 47 * 60000 + 14000,
            clockRunning: true,
          )
        : null,
    broadcast: broadcast
        ? const BroadcastInfo(
            state: BroadcastStreamState.live,
            configured: true,
            server: 'rtmp://a.rtmp.youtube.com/live2',
            targetKbps: 4500,
            audio: true,
            bitrateKbps: 4420,
            uptimeMs: 52 * 60000 + 31000,
          )
        : null,
  );
  return _scope(
    locale,
    copy,
    const ViewerPage(),
    overrides: [
      if (web) pageUriProvider.overrideWithValue(Uri.parse('http://192.168.1.20:8080/')),
      viewerSetupProvider.overrideWith(() => _Paired(web: web)),
      sessionLinkProvider.overrideWithValue(null),
      linkStateProvider.overrideWith(() => _Link(copy.camera, status)),
      liveViewProvider.overrideWith(() => _Live(frames[0])),
      viewerClipsProvider.overrideWith(() => _Clips(list)),
      clipTagsProvider.overrideWith(() => _Tags(tags)),
    ],
  );
}

/// Clip [i] of the session, saved a few minutes apart.
SessionClip _clip(int i, Uint8List thumbnail) => SessionClip(
      requestId: 'r$i',
      clipId: 'c$i',
      seconds: 20,
      durationMs: (i.isEven ? 30 : 20) * 1000,
      requestedAt: DateTime(2026, 10, 30, 18, 4 + i * 6),
      phase: SessionClipPhase.ready,
      stored: _PhotoClip('c$i', thumbnail),
      acked: true,
      onCamera: true,
    );

class _Paired extends ViewerSetupNotifier {
  _Paired({required this.web});

  final bool web;

  @override
  ViewerSetup build() => ViewerSetup(base: Uri.parse('http://192.168.1.20:8080'), token: 't', addressFixed: web);
}

class _Link extends LinkStateNotifier {
  _Link(this.name, this.status);

  final String name;
  final CameraStatus status;

  @override
  LinkState? build() => LinkState(
        phase: LinkPhase.connected,
        camera: CameraInfo(protocolVersion: protocolVersion, cameraId: 'cam', name: name),
        status: status,
      );
}

class _Live extends LiveViewNotifier {
  _Live(this.frame);

  final Uint8List frame;

  @override
  LiveViewState build() => LiveViewState(phase: LivePhase.playing, peer: _PhotoPeer(frame));
}

class _PhotoPeer implements LivePeer {
  _PhotoPeer(this.frame);

  final Uint8List frame;

  @override
  Widget buildView() => Image.memory(frame, fit: BoxFit.contain);

  @override
  Future<void> addRemoteCandidate(RtcIce c) async {}

  @override
  Future<String> createAnswer() async => '';

  @override
  Future<void> setRemoteOffer(String sdp) async {}

  @override
  Future<void> dispose() async {}
}

class _Clips extends ViewerClipsNotifier {
  _Clips(this.clips);

  final List<SessionClip> clips;

  @override
  List<SessionClip> build() => clips;
}

class _Tags extends ClipTagsNotifier {
  _Tags(this.tags);

  final Map<String, String> tags;

  @override
  Map<String, String> build() => tags;
}

class _PhotoClip implements StoredClip {
  _PhotoClip(this.clipId, this.image);

  @override
  final String clipId;
  final Uint8List image;

  @override
  int get length => 8 * 1024 * 1024;

  @override
  bool get canDownload => true;

  @override
  String? get filePath => null;

  @override
  VideoPlayerController createPlayer() => _StillVideo();

  @override
  Future<void> download(String fileName) async {}

  @override
  Future<Uint8List?> thumbnail() async => image;

  @override
  Future<void> release() async {}
}

/// A paused 20 s clip whose picture is [_StillVideoPlatform]'s photo.
class _StillVideo extends VideoPlayerController {
  _StillVideo() : super.networkUrl(Uri.parse('blob:still'));

  @override
  int get playerId => 1;

  @override
  Future<void> initialize() async => value = value.copyWith(
        isInitialized: true,
        duration: const Duration(seconds: 20),
        position: const Duration(seconds: 12, milliseconds: 400),
        size: const Size(1920, 1080),
      );

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> setLooping(bool looping) async => value = value.copyWith(isLooping: looping);

  @override
  Future<void> setVolume(double volume) async => value = value.copyWith(volume: volume);

  @override
  Future<void> setPlaybackSpeed(double speed) async => value = value.copyWith(playbackSpeed: speed);

  @override
  Future<void> seekTo(Duration position) async => value = value.copyWith(position: position);

  @override
  Future<Duration?> get position async => value.position;

  // The fake platform has no player to dispose.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {}
}

class _StillPlatform implements PlayerPlatform {
  @override
  SeekRule get seekRule => SeekRule.atOrAfter;

  @override
  Future<FrameTimeline?> loadTimeline() async => null;

  @override
  Future<Duration?> shownFrameTime() async => null;

  @override
  void keepAwake(bool on) {}

  @override
  void dispose() {}
}

class _StillVideoPlatform extends VideoPlayerPlatform {
  _StillVideoPlatform(this.frame);

  final Uint8List frame;

  @override
  Future<void> init() async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => Image.memory(frame, fit: BoxFit.cover);
}
