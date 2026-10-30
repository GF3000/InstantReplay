import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../clips/clip_transfers.dart';
import '../player/frame_timeline.dart';
import '../player/player_platform.dart';
import '../tags/tag_widgets.dart';
import '../tags/tags.dart';
import 'clip_list.dart';

/// Clip review (SPEC §5.1.5, §5.5, §6, UX §3.4): full screen, autoplay loop, 0.25×/0.5×/1×, ±1 frame,
/// scrub, change tag, and Download on web.
///
/// Frame stepping is exact: frames come from the clip's own timestamps ([FrameTimeline]) and each
/// step seeks to a position the platform player resolves to that frame ([SeekRule]).
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.clip, this.playerFactory, this.platformFactory});

  /// A ready clip ([SessionClip.stored] set).
  final SessionClip clip;

  /// Tests inject a controller; defaults to [StoredClip.createPlayer].
  final VideoPlayerController Function()? playerFactory;

  /// Tests inject the platform helper; defaults to [PlayerPlatform.new].
  final PlayerPlatform Function(VideoPlayerController player)? platformFactory;

  static const speeds = [0.25, 0.5, 1.0];

  /// Horizontal drag on the video moves one frame per this many logical pixels.
  static const dragPixelsPerFrame = 6.0;

  static Route<void> route(SessionClip clip) =>
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ReviewPage(clip: clip));

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final VideoPlayerController _player;
  late final PlayerPlatform _platform;
  bool _failed = false;
  double _speed = 1;

  /// The clip's frames; a 30 fps grid until the real timestamps are read.
  FrameTimeline? _timeline;

  /// The frame on screen while paused; null while playing (the player knows best then).
  int? _frame;

  /// Seeks run one after another so fast taps on ±1 never overtake each other.
  Future<void> _queue = Future.value();

  /// Playing state before the user started scrubbing.
  bool? _wasPlaying;
  double _dragPixels = 0;

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
      await _player.setLooping(true);
      await _player.setVolume(0); // No audio (D7); also lets browsers autoplay.
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
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _platform.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _serial(Future<void> Function() op) => _queue = _queue.then((_) => mounted ? op() : null);

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _player.setPlaybackSpeed(speed);
  }

  Future<void> _play() async {
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
        title: Text(clipName(l10n, tag, clip.requestedAt), overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            key: const ValueKey('review-tag'),
            onPressed: () => showClipTagPicker(context, clip.requestId),
            icon: Icon(tag == null ? Icons.sell_outlined : Icons.sell, color: tag?.colour),
            label: Text(l10n.viewerClipChangeTag),
          ),
          if (stored.canDownload)
            IconButton(
              tooltip: l10n.viewerClipDownload,
              icon: const Icon(Icons.download),
              onPressed: () => stored.download(clipFileName(clip)),
            ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? Center(child: Text(l10n.viewerReviewError, style: Theme.of(context).textTheme.titleMedium))
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _player,
                builder: (context, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('review-video'),
                      behavior: HitTestBehavior.opaque,
                      onTap: v.isInitialized ? _togglePlay : null,
                      onHorizontalDragStart: v.isInitialized ? (_) => _scrubStart() : null,
                      onHorizontalDragUpdate: v.isInitialized ? (d) => _dragBy(d.delta.dx) : null,
                      onHorizontalDragEnd: v.isInitialized ? (_) => _scrubEnd() : null,
                      onHorizontalDragCancel: v.isInitialized ? _scrubEnd : null,
                      child: Center(
                        child: v.isInitialized
                            ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_player))
                            : const CircularProgressIndicator(),
                      ),
                    ),
                  ),
                  _scrubBar(v),
                  _controls(l10n, v),
                ]),
              ),
      ),
    );
  }

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
