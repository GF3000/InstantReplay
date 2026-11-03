import 'package:flutter/material.dart';

import '../clips/clip_transfers.dart';
import '../tags/tags.dart';
import 'review_page.dart';

/// "Watch all" (library): [clips] one after another in the review, each played once.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.clips, this.labelChoices});

  /// In playing order; at least one.
  final List<SessionClip> clips;
  final ClipLabelChoices? labelChoices;

  static Route<void> route(List<SessionClip> clips, {ClipLabelChoices? labelChoices}) => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PlaylistPage(clips: clips, labelChoices: labelChoices),
  );

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  int _index = 0;
  double _speed = 1;

  /// Bumped on every move, so even "watch again" on a single clip starts a fresh player.
  int _run = 0;

  void _go(int index) => setState(() {
    _index = index;
    _run++;
  });

  @override
  Widget build(BuildContext context) {
    final clip = widget.clips[_index];
    final last = widget.clips.length - 1;
    // A new key per clip: each gets its own player, set up from scratch.
    return ReviewPage(
      key: ValueKey('playlist-$_run'),
      clip: clip,
      labelChoices: widget.labelChoices,
      playlist: ReviewPlaylist(
        index: _index,
        length: widget.clips.length,
        onPrevious: _index == 0 ? null : () => _go(_index - 1),
        onNext: () => _go(_index == last ? 0 : _index + 1),
        speed: _speed,
        onSpeed: (s) => _speed = s,
      ),
    );
  }
}
