import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../clips/clip_transfers.dart';
import '../player/frame_timeline.dart';
import '../player/player_platform.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
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
/// is not kept: Done, Play or a frame step clears it.
///
/// Two fingers zoom the video and pan it, playing, paused or drawing (the drawing zooms with it);
/// one finger still scrubs, or draws.
///
/// Frame stepping is exact: frames come from the clip's own timestamps ([FrameTimeline]) and each
/// step seeks to a position the platform player resolves to that frame ([SeekRule]).
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({
    super.key,
    required this.clip,
    this.labelChoices,
    this.playlist,
    this.playerFactory,
    this.platformFactory,
    this.replayBar = false,
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

  /// A clip of the live session: while it is on air (SPEC §12.6) the replay bar shows on top.
  final bool replayBar;

  static const speeds = [0.25, 0.5, 1.0];

  /// Horizontal drag on the video moves one frame per this many logical pixels.
  static const dragPixelsPerFrame = 6.0;

  static Route<void> route(SessionClip clip, {ClipLabelChoices? labelChoices, bool replayBar = false}) =>
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReviewPage(clip: clip, labelChoices: labelChoices, replayBar: replayBar),
      );

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final VideoPlayerController _player;
  late final PlayerPlatform _platform;
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

  @override
  void initState() {
    super.initState();
    _player = (widget.playerFactory ?? widget.clip.stored!.createPlayer)();
    _platform = (widget.platformFactory ?? PlayerPlatform.new)(_player);
    _player.addListener(_onPlayer);
    _init();
  }

  Future<void> _init() async {
    final timeline = _platform.loadTimeline();
    try {
      await _player.initialize();
      _timeline = FrameTimeline.uniform(_player.value.duration);
      await _player.setLooping(widget.playlist == null);
      await _player.setVolume(0); // No audio (D7); also lets browsers autoplay.
      if (_speed != 1) await _player.setPlaybackSpeed(_speed);
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final parsed = await timeline;
    if (parsed != null && mounted) _timeline = parsed;
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

  @override
  void dispose() {
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
    _wasPlaying = _player.value.isPlaying;
    _dragPixels = 0;
    _serial(() => _pause());
  }

  /// Slider: [fraction] of the whole clip.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clip = widget.clip;
    final stored = clip.stored!;
    final tag = ref.watch(clipTagProvider(clip.requestId));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          [
            if (widget.playlist case final p?) l10n.viewerReviewPlaylistPosition(p.index + 1, p.length),
            clipName(l10n, tag, clip.requestedAt),
          ].join(' · '),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('review-draw'),
            tooltip: l10n.viewerDraw,
            isSelected: _drawMode,
            icon: const Icon(Icons.draw_outlined),
            selectedIcon: const Icon(Icons.draw),
            onPressed: _failed ? null : (_drawMode ? _endDrawing : _startDrawing),
          ),
          TextButton.icon(
            key: const ValueKey('review-tag'),
            onPressed: () => showClipTagPicker(context, clip.requestId, choices: widget.labelChoices),
            icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
            label: Text(l10n.viewerClipChangeTag),
          ),
          if (stored.canDownload)
            IconButton(
              tooltip: l10n.viewerClipDownload,
              icon: const Icon(Icons.download),
              onPressed: () => stored.download(clipFileName(clip)),
            ),
          ClipExportActions(stored: stored, fileName: clipFileName(clip)),
        ],
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.replayBar && clip.clipId != null) ViewerReplayBar(clipId: clip.clipId),
          Expanded(child: _body(l10n)),
        ]),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) => _failed
            ? Center(child: Text(l10n.viewerReviewError, style: Theme.of(context).textTheme.titleMedium))
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _player,
                builder: (context, v, _) {
                  // While drawing, the finger draws instead of toggling play or scrubbing.
                  final gestures = v.isInitialized && !_drawMode;
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: Listener(
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
                                    ListenableBuilder(
                                      listenable: _zoom,
                                      builder: (context, _) => !_zoom.zoomed
                                          ? const SizedBox.shrink()
                                          : Align(
                                              alignment: Alignment.topRight,
                                              child: Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Tooltip(
                                                  message: l10n.viewerReviewZoomReset,
                                                  child: FilledButton.tonalIcon(
                                                    key: const ValueKey('review-zoom-reset'),
                                                    onPressed: _zoom.reset,
                                                    icon: const Icon(Icons.zoom_out_map),
                                                    label: Text('×${_zoom.scale.toStringAsFixed(1)}'),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ]),
                                )
                              : const CircularProgressIndicator(),
                        ),
                      ),
                    ),
                  ),
                  if (_drawMode) TelestratorToolbar(controller: _drawing, onDone: _endDrawing) else _scrubBar(v),
                  _controls(l10n, v),
                  ]);
                },
              );

  Widget _scrubBar(VideoPlayerValue v) {
    final total = v.duration.inMilliseconds;
    final ready = v.isInitialized && total > 0;
    final pos = v.position.inMilliseconds.clamp(0, total == 0 ? 0 : total);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text(_fmt(v.position)),
        Expanded(
          child: Slider(
            value: total == 0 ? 0 : pos / total,
            onChangeStart: ready ? (_) => _scrubStart() : null,
            onChanged: ready ? _scrubTo : null,
            onChangeEnd: ready ? (_) => _scrubEnd() : null,
          ),
        ),
        Text(_fmt(v.duration)),
      ]),
    );
  }

  Widget _controls(AppLocalizations l10n, VideoPlayerValue v) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.playlist case final p?)
              IconButton(
                key: const ValueKey('review-prev-clip'),
                iconSize: 32,
                tooltip: l10n.viewerReviewPrevClip,
                onPressed: p.onPrevious,
                icon: const Icon(Icons.keyboard_double_arrow_left),
              ),
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: l10n.viewerReviewPrevFrame,
              onPressed: v.isInitialized ? () => _step(-1) : null,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton.filled(
              iconSize: 40,
              tooltip: v.isPlaying ? l10n.viewerReviewPause : l10n.viewerReviewPlay,
              onPressed: v.isInitialized ? _togglePlay : null,
              icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            IconButton.filledTonal(
              iconSize: 32,
              tooltip: l10n.viewerReviewNextFrame,
              onPressed: v.isInitialized ? () => _step(1) : null,
              icon: const Icon(Icons.skip_next),
            ),
            if (widget.playlist case final p?)
              IconButton(
                key: const ValueKey('review-next-clip'),
                iconSize: 32,
                tooltip: p.isLast ? l10n.viewerReviewPlaylistRestart : l10n.viewerReviewNextClip,
                onPressed: p.onNext,
                icon: Icon(p.isLast ? Icons.replay : Icons.keyboard_double_arrow_right),
              ),
            const SizedBox(width: 16),
            SegmentedButton<double>(
              segments: [
                for (final s in ReviewPage.speeds) ButtonSegment(value: s, label: Text(l10n.viewerReviewSpeed(s))),
              ],
              selected: {_speed},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setSpeed(s.first),
            ),
          ],
        ),
      );

  static String _fmt(Duration d) {
    final s = d.inMilliseconds / 1000;
    return s.toStringAsFixed(1);
  }
}

enum _VideoGesture { undecided, scrub, zoom, none }
