import 'dart:async';
import 'dart:typed_data';

import 'package:instant_replay/features/viewer/clips/clip_store.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:video_player/video_player.dart';

class MemoryClipStore implements ClipStore {
  final stored = <String, Uint8List>{};

  @override
  Future<StoredClip> store(String clipId, Uint8List bytes) async {
    stored[clipId] = bytes;
    return MemoryClip(clipId, bytes.length);
  }
}

class MemoryClip implements StoredClip {
  MemoryClip(this.clipId, this.length);

  @override
  final String clipId;
  @override
  final int length;
  bool released = false;

  @override
  bool get canDownload => false;

  @override
  VideoPlayerController createPlayer() => throw UnimplementedError();

  @override
  Future<void> download(String fileName) async {}

  @override
  Future<Uint8List?> thumbnail() async => null;

  @override
  Future<void> release() async => released = true;
}

/// In-memory WebSocket: the test plays the Camera.
class FakeChannel implements SessionChannel {
  final _incoming = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  /// Camera → Viewer.
  void push(String text) => _incoming.add(text);

  /// Camera hangs up.
  Future<void> drop() => _incoming.close();

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }
}
