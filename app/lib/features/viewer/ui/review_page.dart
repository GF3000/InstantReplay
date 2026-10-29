import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../clips/clip_store.dart';

/// Clip review (SPEC §5.1.5, §6): autoplay loop, 0.25×/0.5×/1×, ±1 frame, scrub.
///
/// Frame stepping seeks by 1/30 s and is approximate, which is enough for S1 (media_kit later).
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.clip, required this.title, this.playerFactory});

  final StoredClip clip;
  final String title;

  /// Tests inject a controller; defaults to [StoredClip.createPlayer].
  final VideoPlayerController Function()? playerFactory;

  static const speeds = [0.25, 0.5, 1.0];
  static const frameStep = Duration(microseconds: 1000000 ~/ 30);

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final VideoPlayerController _player;
  bool _failed = false;
  double _speed = 1;

  /// Playing state before the user started scrubbing.
  bool? _wasPlaying;

  @override
  void initState() {
    super.initState();
    _player = (widget.playerFactory ?? widget.clip.createPlayer)();
    _player.addListener(_onPlayer);
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.initialize();
      await _player.setLooping(true);
      await _player.setVolume(0); // No audio (D7); also lets browsers autoplay.
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onPlayer() {
    if (_player.value.hasError && !_failed) setState(() => _failed = true);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _player.dispose();
    super.dispose();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _player.setPlaybackSpeed(speed);
  }

  Future<void> _step(int frames) async {
    await _player.pause();
    final duration = _player.value.duration;
    var target = _player.value.position + ReviewPage.frameStep * frames;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    await _player.seekTo(target);
  }

  Future<void> _togglePlay() async {
    if (_player.value.isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _failed
            ? Center(child: Text(l10n.viewerReviewError, style: Theme.of(context).textTheme.titleMedium))
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _player,
                builder: (context, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _togglePlay,
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
    final pos = v.position.inMilliseconds.clamp(0, total == 0 ? 0 : total);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        Text(_fmt(v.position)),
        Expanded(
          child: Slider(
            value: total == 0 ? 0 : pos / total,
            onChangeStart: total == 0
                ? null
                : (_) {
                    _wasPlaying = v.isPlaying;
                    _player.pause();
                  },
            onChanged: total == 0 ? null : (x) => _player.seekTo(Duration(milliseconds: (x * total).round())),
            onChangeEnd: (_) {
              if (_wasPlaying ?? false) _player.play();
              _wasPlaying = null;
            },
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
