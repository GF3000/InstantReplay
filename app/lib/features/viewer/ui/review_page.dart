import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart' show ReplayInfo;
import 'package:video_player/video_player.dart';

import '../../../core/capabilities.dart';
import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../clips/clip_transfers.dart';
import '../player/frame_timeline.dart';
import '../player/player_platform.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import '../viewer_providers.dart';
import 'clip_export_actions.dart';
import 'clip_list.dart';
import 'replay_air.dart';
import 'telestrator.dart';
import 'video_zoom.dart';

/// Where a clip sits in a "Watch all" run, and how to move on.
@immutable
class ReviewPlaylist {
  const ReviewPlaylist({
    required this.index,
    required this.length,
    required this.onPrevious,
    required this.onNext,
    required this.speed,
    required this.onSpeed,
  });

  final int index;
  final int length;

  /// Null on the first clip.
  final VoidCallback? onPrevious;

  /// The next clip; on the last one, back to the first.
  final VoidCallback onNext;

  /// Playback speed, kept from clip to clip.
  final double speed;
  final ValueChanged<double> onSpeed;

  bool get isLast => index == length - 1;
}

/// Clip review (SPEC §5.1.5, §5.5, §6, UX §3.4): full screen, autoplay loop, 0.25×/0.5×/1×, ±1 frame,
/// scrub, change tag, and Download on web or Save to gallery / Share on Android.
///
/// In a playlist ([ReviewPlaylist], the library's "Watch all") each clip plays once and the next one
/// follows; otherwise the clip loops.
///
/// Draw mode pauses on the frame and lets the coach draw over it ([TelestratorCanvas]). The drawing
/// is not kept: Done, Play, a frame step or a scrub clears it.
///
/// Two fingers zoom the video and pan it, playing, paused or drawing (the drawing zooms with it);
/// one finger still scrubs, or draws.
///
/// Frame stepping is exact: frames come from the clip's own timestamps ([FrameTimeline]) and each
/// step seeks to a position the platform player resolves to that frame ([SeekRule]).
///
/// Reviewing plays on this tablet only. While the stream is on, a clip of the live session that is
/// still on the Camera has an explicit "Air replay" button (SPEC §12.6): it goes on air at the
/// current speed and the tablet then mirrors the stream.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({
    super.key,
    required this.clip,
    this.labelChoices,
    this.playlist,
    this.playerFactory,
    this.platformFactory,
    this.replayBar = false,
    this.onAir = false,
  });

  /// A ready clip ([SessionClip.stored] set).
  final SessionClip clip;

  /// The labels the tag picker offers for a clip outside the active session (library review);
  /// null for the active session's own.
  final ClipLabelChoices? labelChoices;

  /// Set when this clip is one of several played in a row.
  final ReviewPlaylist? playlist;

  /// Tests inject a controller; defaults to [StoredClip.createPlayer].
  final VideoPlayerController Function()? playerFactory;

  /// Tests inject the platform helper; defaults to [PlayerPlatform.new].
  final PlayerPlatform Function(VideoPlayerController player)? platformFactory;

  /// A clip of the live session: it can be put on air from here (SPEC §12.6), and while it is on
  /// air the replay bar shows on top.
  final bool replayBar;

  /// The clip was put on air before the page opened: the tablet mirrors the stream. One speed
  /// control drives both, the local player follows the stream's position and speed, and leaving
  /// the page goes back to live.
  final bool onAir;

  static const speeds = [0.25, 0.5, 1.0];

  /// Horizontal drag on the video moves one frame per this many logical pixels.
  static const dragPixelsPerFrame = 6.0;

  static Route<void> route(
    SessionClip clip, {
    ClipLabelChoices? labelChoices,
    bool replayBar = false,
    bool onAir = false,
  }) =>
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReviewPage(clip: clip, labelChoices: labelChoices, replayBar: replayBar, onAir: onAir),
      );

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

/// How the page is laid out for the screen it is on.
enum _Layout {
  /// Tablet, laptop or a big phone sideways: transport in two rows, palette on the left.
  wide,

  /// A phone sideways (little height): one compact transport row, hidden while drawing.
  compact,

  /// A phone held upright: transport stacked under the video, palette at the bottom.
  stacked,

  /// A tablet held upright: the wide transport, palette at the bottom.
  tall;

  static _Layout of(Size size) {
    final portrait = size.height > size.width;
    if (!portrait) return size.height < 500 ? compact : wide;
    return size.width < 600 ? stacked : tall;
  }

  bool get portrait => this == stacked || this == tall;
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late VideoPlayerController _player;
  late PlayerPlatform _platform;
  bool _failed = false;
  late double _speed = widget.playlist?.speed ?? 1;

  /// The playlist moved on from this clip already (completion is reported more than once).
  bool _advanced = false;

  /// The clip's frames; a 30 fps grid until the real timestamps are read.
  FrameTimeline? _timeline;

  /// The frame on screen while paused; null while playing (the player knows best then).
  int? _frame;

  /// Seeks run one after another so fast taps on ±1 never overtake each other.
  Future<void> _queue = Future.value();

  /// Playing state before the user started scrubbing.
  bool? _wasPlaying;
  double _dragPixels = 0;

  final _drawing = TelestratorController();
  bool _drawMode = false;

  final _zoom = VideoZoomController();

  /// The video's box, unzoomed: pinch points are taken in it.
  final _videoBox = GlobalKey();

  /// What the current gesture on the video does, once known; [_multiTouch] once two fingers were
  /// down (the finger left after a pinch does not scrub).
  _VideoGesture? _gesture;
  bool _multiTouch = false;
  int _fingers = 0;

  /// The tablet mirrors the stream: the clip was put on air from here (or before the page opened).
  late bool _mirror = widget.onAir;
  bool _following = false;

  /// This clip has been on air since it was put on air from here; it is the one to stop on leaving.
  bool _aired = false;
  late final ViewerBroadcastNotifier _remote;

  final _exporter = ClipExporter();

  @override
  void initState() {
    super.initState();
    _remote = ref.read(viewerBroadcastNoticeProvider.notifier);
    _open();
    if (widget.onAir) _follow();
  }

  void _open() {
    _player = (widget.playerFactory ?? widget.clip.stored!.createPlayer)();
    _platform = (widget.platformFactory ?? PlayerPlatform.new)(_player);
    _player.addListener(_onPlayer);
    _init();
  }

  /// Mirror the stream: its speed and position drive the local player.
  void _follow() {
    if (_following) return;
    _following = true;
    ref.listenManual(viewerReplayProvider, (_, replay) => _onReplay(replay), fireImmediately: true);
  }

  Future<void> _init() async {
    final player = _player;
    final timeline = _platform.loadTimeline();
    try {
      await player.initialize();
      _timeline = FrameTimeline.uniform(player.value.duration);
      // On air the clip plays once, like the stream.
      await player.setLooping(widget.playlist == null && !_mirror);
      await player.setVolume(0); // No audio (D7); also lets browsers autoplay.
      if (_speed != 1) await player.setPlaybackSpeed(_speed);
      await player.play();
    } catch (_) {
      if (mounted && identical(player, _player)) setState(() => _failed = true);
      return;
    }
    final parsed = await timeline;
    if (parsed != null && mounted && identical(player, _player)) setState(() => _timeline = parsed);
  }

  /// The clip could not be played: a fresh player tries again.
  void _retry() {
    final player = _player, platform = _platform;
    player.removeListener(_onPlayer);
    setState(() {
      _failed = false;
      _timeline = null;
      _frame = null;
      _advanced = false;
      _queue = Future.value();
      _open();
    });
    platform.dispose();
    unawaited(player.dispose());
  }

  void _onPlayer() {
    if (_player.value.hasError && !_failed) setState(() => _failed = true);
    // Watch all: the next clip follows when this one ends; the last one stays on its end.
    final playlist = widget.playlist;
    if (playlist != null && _player.value.isCompleted && !_advanced && !_drawMode && !playlist.isLast) {
      _advanced = true;
      playlist.onNext();
    }
  }

  /// The replay on air changed: follow its speed, and its position when it starts or drifts.
  void _onReplay(ReplayInfo? replay) {
    if (replay == null || replay.clipId != widget.clip.clipId) {
      // It ended on the Camera, or another clip replaced it: the stream is back on live.
      _aired = false;
      return;
    }
    final started = !_aired;
    _aired = true;
    if (replay.speed != _speed) {
      setState(() => _speed = replay.speed);
      unawaited(_player.setPlaybackSpeed(replay.speed));
    }
    final local = _player.value.position.inMilliseconds;
    if (started || (local - replay.positionMs).abs() > _maxDriftMs) {
      unawaited(_serial(() async {
        await _player.seekTo(Duration(milliseconds: replay.positionMs));
        if (!_drawMode) {
          _frame = null;
          await _player.play();
        }
      }));
    }
  }

  /// Tablet and stream may drift this far apart before the tablet jumps to the stream.
  static const _maxDriftMs = 600;

  /// "Air replay": the clip goes on air at the current speed and the tablet mirrors the stream.
  void _goOnAir() {
    final clipId = widget.clip.clipId;
    if (clipId == null || !_remote.replayAir(clipId, speed: _speed)) return;
    setState(() => _mirror = true);
    unawaited(_player.setLooping(false));
    _follow();
  }

  /// "Take off air": the stream goes back to live; the review stays open on the tablet.
  void _takeOffAir() {
    _remote.replayStop();
    _aired = false;
  }

  /// Back to live from this page: stops the replay and closes the page.
  void _backToLive() {
    _remote.replayStop();
    _aired = false;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    // Leaving the page ends the replay on air: the stream goes back to live.
    if (_mirror && _aired) _remote.replayStop();
    _player.removeListener(_onPlayer);
    _platform.dispose();
    _player.dispose();
    _drawing.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _serial(Future<void> Function() op) => _queue = _queue.then((_) => mounted ? op() : null);

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    widget.playlist?.onSpeed(speed);
    // On air, one control: the stream changes speed with the tablet.
    if (_mirror && _aired) _remote.replaySpeed(speed);
    await _player.setPlaybackSpeed(speed);
  }

  /// Pauses on the frame on screen and starts drawing over it.
  Future<void> _startDrawing() => _serial(() async {
        await _pause();
        if (mounted) setState(() => _drawMode = true);
      });

  /// Leaves draw mode; the drawing goes with it.
  void _endDrawing() {
    if (!_drawMode) return;
    _drawing.reset();
    if (mounted) setState(() => _drawMode = false);
  }

  void _toggleDrawing() => _drawMode ? _endDrawing() : _startDrawing();

  Future<void> _play() async {
    _endDrawing();
    // A playlist clip that ended stays on its last frame: Play starts it again.
    if (_player.value.isCompleted) await _player.seekTo(Duration.zero);
    _frame = null;
    _platform.keepAwake(false);
    await _player.play();
  }

  /// Pauses and snaps to a whole frame, so the next step starts from the frame on screen.
  Future<int> _pause() async {
    final frame = _frame;
    if (frame != null) return frame;
    await _player.pause();
    _platform.keepAwake(true);
    final timeline = _timeline!;
    final shown = await _platform.shownFrameTime() ?? _player.value.position;
    final snapped = timeline.indexAt(shown);
    await _show(snapped);
    return snapped;
  }

  Future<void> _show(int frame) async {
    _frame = frame;
    await _player.seekTo(_timeline!.seekTarget(frame, _platform.seekRule));
  }

  Future<void> _step(int frames) => _serial(() async {
        _endDrawing(); // The drawing belongs to the frame it was made on.
        final from = await _pause();
        await _show(_timeline!.step(from, frames));
      });

  Future<void> _togglePlay() => _serial(() async {
        if (_player.value.isPlaying) {
          await _pause();
        } else {
          await _play();
        }
      });

  void _scrubStart() {
    _endDrawing();
    _wasPlaying = _player.value.isPlaying;
    _dragPixels = 0;
    _serial(() => _pause());
  }

  /// Scrubber: [fraction] of the whole clip.
  void _scrubTo(double fraction) {
    final timeline = _timeline!;
    final frame = timeline.indexAt(timeline.duration * fraction);
    _seekCoalesced((_) => frame);
  }

  /// Drag on the video: one frame every [ReviewPage.dragPixelsPerFrame].
  void _dragBy(double dx) {
    _dragPixels += dx;
    final frames = (_dragPixels / ReviewPage.dragPixelsPerFrame).truncate();
    if (frames == 0) return;
    _dragPixels -= frames * ReviewPage.dragPixelsPerFrame;
    final previous = _scrubTarget;
    _seekCoalesced((from) => _timeline!.step(previous?.call(from) ?? from, frames));
  }

  RenderBox? get _videoRender => _videoBox.currentContext?.findRenderObject() as RenderBox?;

  void _zoomStart(Offset global) {
    if (_videoRender case final box?) _zoom.begin(box.globalToLocal(global));
  }

  void _zoomUpdate(Offset global, double scale) {
    if (_videoRender case final box?) _zoom.update(box.globalToLocal(global), scale, box.size);
  }

  /// One finger scrubs (once it moves sideways); two zoom.
  void _gestureStart(ScaleStartDetails d) {
    if (d.pointerCount > 1) {
      _multiTouch = true;
      _gesture = _VideoGesture.zoom;
      _zoomStart(d.focalPoint);
    } else {
      _gesture = _multiTouch ? _VideoGesture.none : _VideoGesture.undecided;
    }
  }

  void _gestureUpdate(ScaleUpdateDetails d) {
    switch (_gesture) {
      case _VideoGesture.undecided:
        final m = d.focalPointDelta;
        if (m == Offset.zero) return;
        if (m.dx.abs() >= m.dy.abs()) {
          _gesture = _VideoGesture.scrub;
          _scrubStart();
          _dragBy(m.dx);
        } else {
          _gesture = _VideoGesture.none;
        }
      case _VideoGesture.scrub:
        _dragBy(d.focalPointDelta.dx);
      case _VideoGesture.zoom:
        _zoomUpdate(d.focalPoint, d.scale);
      case _VideoGesture.none || null:
        break;
    }
  }

  void _gestureEnd(ScaleEndDetails d) {
    if (_gesture == _VideoGesture.scrub) _scrubEnd();
    _gesture = null;
  }

  /// Scrub events arrive faster than seeks finish: only the latest target is shown.
  int Function(int from)? _scrubTarget;

  void _seekCoalesced(int Function(int from) target) {
    final queued = _scrubTarget != null;
    _scrubTarget = target;
    if (queued) return;
    _serial(() async {
      final from = await _pause();
      final frame = _scrubTarget!(from);
      _scrubTarget = null;
      await _show(frame);
    });
  }

  void _scrubEnd() {
    if (_wasPlaying ?? false) _serial(_play);
    _wasPlaying = null;
  }

  // ---------------------------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clip = widget.clip;
    final tag = ref.watch(clipTagProvider(clip.requestId));
    final layout = _Layout.of(MediaQuery.sizeOf(context));
    final live = widget.replayBar && clip.clipId != null;
    final streaming = live && (ref.watch(viewerBroadcastProvider)?.active ?? false);
    final airing = live && ref.watch(viewerReplayProvider.select((r) => r != null && r.clipId == clip.clipId));
    final air = airing || canGoOnAir(clip, streaming: streaming)
        ? _AirButton(
            airing: airing,
            labelled: MediaQuery.sizeOf(context).width >= 600,
            onPressed: airing ? _takeOffAir : _goOnAir,
          )
        : null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: layout == _Layout.compact ? 48 : 60,
        titleSpacing: 0,
        title: _title(l10n, tag, compact: layout == _Layout.compact),
        actions: [
          ..._actions(l10n, tag, air),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (live) ViewerReplayBar(clipId: clip.clipId, speed: !_mirror, onStop: _mirror ? _backToLive : null),
          Expanded(child: _failed ? _error(l10n) : _playerView(l10n, layout, airing: airing)),
        ]),
      ),
    );
  }

  /// Tag colour, clip name and a mono line: duration, and the place in a playlist.
  Widget _title(AppLocalizations l10n, ViewerTag? tag, {required bool compact}) {
    final c = context.ir;
    final clip = widget.clip;
    final meta = [
      l10n.viewerClipDuration(clipSeconds(clip)),
      if (widget.playlist case final p?) l10n.reviewClipOf(p.index + 1, p.length),
    ].join(' · ');
    return Row(children: [
      Container(
        width: 6,
        height: compact ? 22 : 28,
        decoration: BoxDecoration(color: tag?.colour ?? c.lineStrong, borderRadius: BorderRadius.circular(1)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            clipName(l10n, tag, clip.requestedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 17 : 19, height: 1.15, fontWeight: FontWeight.w700, color: c.text),
          ),
          Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: irMono(12, weight: FontWeight.w500, color: c.muted)),
        ]),
      ),
    ]);
  }

  /// Wide screens: labelled outlined buttons. Medium: Draw and Tag as icons. A phone: Draw and Air
  /// (an icon) stay, Tag and Export go in a menu.
  List<Widget> _actions(AppLocalizations l10n, ViewerTag? tag, Widget? air) {
    final c = context.ir;
    final clip = widget.clip;
    final stored = clip.stored!;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final selected = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(_drawMode ? c.signalSoft : Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(_drawMode ? c.signal : c.text),
      side: WidgetStatePropertyAll(BorderSide(color: _drawMode ? c.signal : c.line)),
      minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
    );
    void changeTag() => showClipTagPicker(context, clip.requestId, choices: widget.labelChoices);
    if (wide) {
      const gap = SizedBox(width: 8);
      return [
        OutlinedButton.icon(
          key: const ValueKey('review-draw'),
          style: selected,
          onPressed: _failed ? null : _toggleDrawing,
          icon: Icon(_drawMode ? Icons.draw : Icons.draw_outlined),
          label: Text(_drawMode ? l10n.reviewDrawActive : l10n.reviewDraw),
        ),
        gap,
        OutlinedButton.icon(
          key: const ValueKey('review-tag'),
          style: ButtonStyle(
            side: WidgetStatePropertyAll(BorderSide(color: c.line)),
            minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          ),
          onPressed: changeTag,
          icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
          label: Text(l10n.reviewChangeTag),
        ),
        gap,
        ClipExportActions(stored: stored, fileName: clipFileName(clip)),
        if (air != null) ...[gap, air],
      ];
    }
    final draw = IconButton(
      key: const ValueKey('review-draw'),
      tooltip: l10n.viewerDraw,
      isSelected: _drawMode,
      style: selected,
      icon: const Icon(Icons.draw_outlined),
      selectedIcon: const Icon(Icons.draw),
      onPressed: _failed ? null : _toggleDrawing,
    );
    if (MediaQuery.sizeOf(context).width >= 600) {
      // Medium: Draw and Tag as icons, Export and Air keep their labels.
      return [
        draw,
        IconButton(
          key: const ValueKey('review-tag'),
          tooltip: l10n.reviewChangeTag,
          onPressed: changeTag,
          icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
        ),
        const SizedBox(width: 4),
        ClipExportActions(stored: stored, fileName: clipFileName(clip)),
        if (air != null) ...[const SizedBox(width: 8), air],
      ];
    }
    final exports = clipExportKinds(ref.watch(capabilitiesProvider), stored);
    return [
      draw,
      if (air != null) ...[const SizedBox(width: 6), air],
      PopupMenuButton<VoidCallback>(
        key: const ValueKey('review-more'),
        tooltip: l10n.reviewMore,
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const ValueKey('review-tag'),
            value: changeTag,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
              title: Text(l10n.reviewChangeTag),
            ),
          ),
          for (final kind in exports)
            PopupMenuItem(
              key: kind.key,
              value: () => _exporter.run(this.context, kind, stored, clipFileName(clip)),
              child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(kind.icon), title: Text(kind.label(l10n))),
            ),
        ],
      ),
    ];
  }

  Widget _error(AppLocalizations l10n) {
    final c = context.ir;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: IrPanel(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline, size: 40, color: c.warn),
                const SizedBox(height: 12),
                Text(
                  l10n.viewerReviewError,
                  key: const ValueKey('review-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('review-retry'),
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.reviewRetry),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerView(AppLocalizations l10n, _Layout layout, {required bool airing}) =>
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _player,
        builder: (context, v, _) {
          final video = _videoArea(l10n, v, layout, airing: airing);
          final palette = _drawMode && layout.portrait
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: TelestratorToolbar(controller: _drawing, onDone: _endDrawing, axis: Axis.horizontal),
                    ),
                  ),
                )
              : null;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: video),
            // A phone sideways keeps the height for the video while drawing: Play, a step or a
            // scrub would end the drawing anyway.
            if (!(layout == _Layout.compact && _drawMode)) _transport(l10n, v, layout),
            ?palette,
          ]);
        },
      );

  Widget _videoArea(AppLocalizations l10n, VideoPlayerValue v, _Layout layout, {required bool airing}) {
    final c = context.ir;
    // While drawing, the finger draws instead of toggling play or scrubbing.
    final gestures = v.isInitialized && !_drawMode;
    final frame = _frameOn(v);
    final timeline = _timeline;
    final video = Listener(
      onPointerDown: (_) {
        if (_fingers++ == 0) _multiTouch = false;
      },
      onPointerUp: (_) => _fingers--,
      onPointerCancel: (_) => _fingers--,
      child: GestureDetector(
        key: const ValueKey('review-video'),
        behavior: HitTestBehavior.opaque,
        onTap: gestures ? _togglePlay : null,
        onScaleStart: gestures ? _gestureStart : null,
        onScaleUpdate: gestures ? _gestureUpdate : null,
        onScaleEnd: gestures ? _gestureEnd : null,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: v.isInitialized
                ? AspectRatio(
                    key: _videoBox,
                    aspectRatio: v.aspectRatio,
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRect(
                        child: ListenableBuilder(
                          listenable: _zoom,
                          builder: (context, child) => Transform(transform: _zoom.matrix, child: child),
                          child: Stack(fit: StackFit.expand, children: [
                            VideoPlayer(_player),
                            if (_drawMode)
                              TelestratorCanvas(
                                controller: _drawing,
                                enabled: true,
                                onZoomStart: _zoomStart,
                                onZoomUpdate: _zoomUpdate,
                              ),
                          ]),
                        ),
                      ),
                      // Frame counter and speed.
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IgnorePointer(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (frame != null && timeline != null)
                              _Overlay(
                                l10n.reviewFrameCounter(frame + 1, timeline.length),
                                key: const ValueKey('review-frame'),
                                color: c.signal,
                              ),
                            const SizedBox(width: 4),
                            _Overlay(l10n.viewerReviewSpeed(_speed), color: Colors.white),
                          ]),
                        ),
                      ),
                      if (airing)
                        Positioned(
                          top: 8,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                key: const ValueKey('review-on-air'),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(color: c.live, borderRadius: BorderRadius.circular(3)),
                                child: Text(
                                  l10n.reviewOnAirBanner,
                                  style: irMono(13, color: c.onLive).copyWith(letterSpacing: 1.2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ListenableBuilder(
                        listenable: _zoom,
                        builder: (context, _) => !_zoom.zoomed
                            ? const SizedBox.shrink()
                            : Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _ZoomChip(
                                    tooltip: l10n.viewerReviewZoomReset,
                                    label: '×${_zoom.scale.toStringAsFixed(1)}',
                                    onTap: _zoom.reset,
                                  ),
                                ),
                              ),
                      ),
                    ]),
                  )
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(l10n.reviewLoading, style: TextStyle(fontSize: 15, color: c.muted)),
                  ]),
          ),
        ),
      ),
    );
    if (!_drawMode || layout.portrait) return video;
    // The palette floats over the left edge; taps between its blocks reach the video.
    return Stack(children: [
      Positioned.fill(child: video),
      Positioned(
        left: 8,
        top: 4,
        bottom: 4,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TelestratorToolbar(
            controller: _drawing,
            onDone: _endDrawing,
            columns: layout == _Layout.compact ? 3 : 2,
          ),
        ),
      ),
    ]);
  }

  /// The frame on screen (0-based), once the clip's frames are known.
  int? _frameOn(VideoPlayerValue v) {
    final timeline = _timeline;
    if (timeline == null || !v.isInitialized) return null;
    return _frame ?? timeline.indexAt(v.position);
  }

  Widget _transport(AppLocalizations l10n, VideoPlayerValue v, _Layout layout) {
    final c = context.ir;
    final ready = v.isInitialized;
    final playlist = widget.playlist;
    final frame = _frameOn(v);
    final total = v.duration.inMilliseconds;
    final scrubber = ReviewScrubber(
      fraction: total == 0 ? 0 : v.position.inMilliseconds.clamp(0, total) / total,
      frame: frame,
      frames: _timeline?.length,
      enabled: ready && total > 0 && _timeline != null,
      onStart: _scrubStart,
      onChanged: _scrubTo,
      onEnd: _scrubEnd,
      onStep: (d) => _step(d),
    );
    final height = layout == _Layout.compact ? 48.0 : 56.0;
    // Key faces centred in the key's full height.
    Widget face(Widget child) => SizedBox(height: height, child: Center(child: child));
    Widget frameKey(int delta) => Tooltip(
          message: delta < 0 ? l10n.viewerReviewPrevFrame : l10n.viewerReviewNextFrame,
          child: IrKey(
            minHeight: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: ready ? () => _step(delta) : null,
            child: face(FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                delta < 0 ? l10n.reviewFrameBack : l10n.reviewFrameForward,
                maxLines: 1,
                style: irMono(15, weight: FontWeight.w600, color: c.text),
              ),
            )),
          ),
        );
    final play = Tooltip(
      message: v.isPlaying ? l10n.viewerReviewPause : l10n.viewerReviewPlay,
      child: IrKey(
        key: const ValueKey('review-play'),
        minHeight: height,
        borderColor: c.signal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onPressed: ready ? _togglePlay : null,
        child: face(Icon(v.isPlaying ? Icons.pause : Icons.play_arrow, size: 30, color: c.signal)),
      ),
    );
    Widget? clipKey(bool next) {
      final p = playlist;
      if (p == null) return null;
      return Tooltip(
        message: next ? (p.isLast ? l10n.viewerReviewPlaylistRestart : l10n.viewerReviewNextClip) : l10n.viewerReviewPrevClip,
        child: IrKey(
          key: ValueKey(next ? 'review-next-clip' : 'review-prev-clip'),
          minHeight: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onPressed: next ? p.onNext : p.onPrevious,
          child: face(Icon(
            next ? (p.isLast ? Icons.replay : Icons.keyboard_double_arrow_right) : Icons.keyboard_double_arrow_left,
            color: c.text,
          )),
        ),
      );
    }

    final speed = KeyedSubtree(
      key: const ValueKey('review-speed'),
      child: IrSegmented<double>(
        values: ReviewPage.speeds,
        labelOf: l10n.viewerReviewSpeed,
        selected: _speed,
        onChanged: _setSpeed,
        mono: true,
      ),
    );
    final prev = clipKey(false), next = clipKey(true);
    final border = BoxDecoration(border: Border(top: BorderSide(color: c.line)));

    switch (layout) {
      case _Layout.compact:
        return Container(
          decoration: border,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(children: [
            if (prev != null) ...[prev, const SizedBox(width: 4)],
            SizedBox(width: 56, child: play),
            const SizedBox(width: 4),
            SizedBox(width: 64, child: frameKey(-1)),
            const SizedBox(width: 4),
            SizedBox(width: 64, child: frameKey(1)),
            if (next != null) ...[const SizedBox(width: 4), next],
            const SizedBox(width: 8),
            // The timecode only where the scrubber keeps its room.
            if (MediaQuery.sizeOf(context).width >= 720) ...[
              Text(_timecode(v.position), style: irMono(14, color: c.signal)),
              const SizedBox(width: 8),
            ],
            Expanded(child: scrubber),
            const SizedBox(width: 8),
            SizedBox(width: 156, child: speed),
          ]),
        );
      case _Layout.stacked:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!_drawMode) ...[
              Row(children: [
                Text(_timecode(v.position), style: irMono(15, color: c.signal)),
                const Spacer(),
                Text(_timecode(v.duration), style: irMono(13, weight: FontWeight.w500, color: c.muted)),
              ]),
              scrubber,
              const SizedBox(height: 6),
            ],
            Row(children: [
              if (prev != null) ...[prev, const SizedBox(width: 6)],
              Expanded(flex: 10, child: frameKey(-1)),
              const SizedBox(width: 6),
              Expanded(flex: 13, child: play),
              const SizedBox(width: 6),
              Expanded(flex: 10, child: frameKey(1)),
              if (next != null) ...[const SizedBox(width: 6), next],
            ]),
            const SizedBox(height: 8),
            speed,
          ]),
        );
      case _Layout.wide || _Layout.tall:
        return Container(
          decoration: border,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            scrubber,
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Flexible(
                    child: Text(
                      _timecode(v.position),
                      key: const ValueKey('review-timecode'),
                      maxLines: 1,
                      style: irMono(22, color: c.signal),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '/ ${_timecode(v.duration)}',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: irMono(13, weight: FontWeight.w500, color: c.muted),
                    ),
                  ),
                ]),
              ),
              if (prev != null) ...[prev, const SizedBox(width: 8)],
              SizedBox(width: 80, child: frameKey(-1)),
              const SizedBox(width: 8),
              SizedBox(width: 96, child: play),
              const SizedBox(width: 8),
              SizedBox(width: 80, child: frameKey(1)),
              if (next != null) ...[const SizedBox(width: 8), next],
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const SizedBox(width: 8),
                  Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 216), child: speed)),
                ]),
              ),
            ]),
          ]),
        );
    }
  }

  /// `00:13.7`
  static String _timecode(Duration d) {
    final tenths = d.inMilliseconds ~/ 100;
    final s = tenths ~/ 10;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(s ~/ 60)}:${two(s % 60)}.${tenths % 10}';
  }
}

enum _VideoGesture { undecided, scrub, zoom, none }

/// A small mono label over the video.
class _Overlay extends StatelessWidget {
  const _Overlay(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(2)),
        child: Text(text, style: irMono(13, weight: FontWeight.w600, color: color)),
      );
}

/// "×2.4": the zoom, and a tap back to the whole picture.
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.tooltip, required this.label, required this.onTap});

  final String tooltip;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Tooltip(
      message: tooltip,
      child: Material(
        key: const ValueKey('review-zoom-reset'),
        color: Colors.black.withValues(alpha: 0.75),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.lineStrong)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.zoom_out_map, size: 20, color: c.signal),
                const SizedBox(width: 6),
                Text(label, style: irMono(14, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Air replay" (outlined in live red) or, while this clip is on air, "Take off air" (filled red,
/// blinking dot).
class _AirButton extends StatelessWidget {
  const _AirButton({required this.airing, required this.labelled, required this.onPressed});

  final bool airing;

  /// False on a narrow phone: the icon only, with a tooltip.
  final bool labelled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final l10n = AppLocalizations.of(context);
    final fg = airing ? c.onLive : c.liveText;
    final label = airing ? l10n.reviewAirStop : l10n.reviewAirSend;
    return Tooltip(
      message: label,
      child: Material(
        key: const ValueKey('review-air'),
        color: airing ? c.live : c.liveSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.live)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: labelled ? 14 : 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (airing) IrLiveDot(color: fg, size: 9) else Icon(Icons.sensors, size: 20, color: fg),
                if (labelled) ...[
                  const SizedBox(width: 8),
                  Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The review's scrubber: a ticked track, the played part tinted, an amber playhead with a glow and
/// its frame number ([frame]) above it, and an optional [marker] diamond under the track (a moment
/// of the clip, in [markerColor]).
///
/// A tap jumps, a horizontal drag scrubs; accessibility increase/decrease step one frame.
class ReviewScrubber extends StatelessWidget {
  const ReviewScrubber({
    super.key = const ValueKey('review-scrubber'),
    required this.fraction,
    required this.enabled,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.onStep,
    this.frame,
    this.frames,
    this.marker,
    this.markerColor,
  });

  /// Where the playhead is, 0..1.
  final double fraction;
  final bool enabled;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  /// One frame back (-1) or on (1), for accessibility.
  final ValueChanged<int>? onStep;

  /// The frame on screen (0-based) and how many there are, once known.
  final int? frame;
  final int? frames;
  final double? marker;
  final Color? markerColor;

  static const height = 48.0;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final f = frame, n = frames;
    final label = f == null ? null : 'F${f + 1}';
    final step = enabled && f != null && n != null ? onStep : null;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double at(Offset p) => width <= 0 ? 0 : (p.dx / width).clamp(0.0, 1.0);
        return Semantics(
          slider: true,
          enabled: enabled,
          value: step == null ? null : label,
          increasedValue: step == null ? null : 'F${(f! + 2).clamp(1, n!)}',
          decreasedValue: step == null ? null : 'F${f!.clamp(1, n!)}',
          onIncrease: step == null ? null : () => step(1),
          onDecrease: step == null ? null : () => step(-1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: enabled
                ? (d) {
                    onStart();
                    onChanged(at(d.localPosition));
                    onEnd();
                  }
                : null,
            onHorizontalDragStart: enabled
                ? (d) {
                    onStart();
                    onChanged(at(d.localPosition));
                  }
                : null,
            onHorizontalDragUpdate: enabled ? (d) => onChanged(at(d.localPosition)) : null,
            onHorizontalDragEnd: enabled ? (_) => onEnd() : null,
            onHorizontalDragCancel: enabled ? onEnd : null,
            child: CustomPaint(
              size: Size(width, height),
              painter: _ScrubPainter(
                fraction: fraction.clamp(0.0, 1.0),
                label: label,
                marker: marker,
                markerColor: markerColor ?? c.ok,
                colors: c,
                enabled: enabled,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter({
    required this.fraction,
    required this.label,
    required this.marker,
    required this.markerColor,
    required this.colors,
    required this.enabled,
  });

  final double fraction;
  final String? label;
  final double? marker;
  final Color markerColor;
  final IrColors colors;
  final bool enabled;

  static const _trackTop = 17.0;
  static const _trackBottom = 35.0;

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors;
    final w = size.width;
    final x = w * fraction;
    // Ticks every 10 px and the base line.
    final tick = Paint()
      ..color = c.lineStrong
      ..strokeWidth = 1;
    for (var t = 0.0; t <= w; t += 10) {
      canvas.drawLine(Offset(t, _trackTop), Offset(t, _trackBottom), tick);
    }
    canvas
      ..drawLine(const Offset(0, _trackBottom), Offset(w, _trackBottom), tick)
      ..drawRect(Rect.fromLTRB(0, _trackTop, x, _trackBottom), Paint()..color = c.signal.withValues(alpha: 0.14));
    if (marker case final m?) {
      final mx = w * m.clamp(0.0, 1.0);
      final diamond = Path()
        ..moveTo(mx, 37)
        ..lineTo(mx + 4.5, 41.5)
        ..lineTo(mx, 46)
        ..lineTo(mx - 4.5, 41.5)
        ..close();
      canvas.drawPath(diamond, Paint()..color = markerColor);
    }
    if (!enabled) return;
    // The playhead, with its glow.
    final head = Rect.fromLTRB(x - 1.5, 12, x + 1.5, 40);
    canvas
      ..drawRect(
        head,
        Paint()
          ..color = c.signal.withValues(alpha: 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      )
      ..drawRect(head, Paint()..color = c.signal);
    if (label case final text?) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: irMono(11, color: c.signal)),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (x - painter.width / 2).clamp(0.0, (w - painter.width).clamp(0.0, double.infinity));
      painter
        ..paint(canvas, Offset(left, 0))
        ..dispose();
    }
  }

  @override
  bool shouldRepaint(_ScrubPainter old) =>
      old.fraction != fraction ||
      old.label != label ||
      old.marker != marker ||
      old.enabled != enabled ||
      old.colors != colors ||
      old.markerColor != markerColor;
}
