import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:uuid/uuid.dart';

import '../broadcast/youtube/youtube_account.dart';
import '../broadcast/youtube/youtube_api.dart';
import 'data/session_link.dart';
import 'viewer_providers.dart';

/// The Camera's YouTube account seen from a viewer (SPEC §12.1). The account lives on the
/// Camera: this reads its state from `status.youtube` and sends `youtube_cmd`, so the stream
/// settings and the share sheet work as on the Camera, but the Camera talks to YouTube. A
/// viewer never signs in or out ([signIn] and [signOut] are not offered), and nothing here
/// reaches Google: the web Viewer stays offline.
///
/// Targets returned by [save] and [ensureLive] carry the Camera's ingest server and an empty
/// key: the key stays on the Camera, which already streams to it.
class RemoteYouTubeAccount implements YouTubeAccount {
  RemoteYouTubeAccount({required this._send, this.timeout = const Duration(seconds: 60)});

  final bool Function(WsMessage) _send;

  /// How long a command may take on the Camera (creating a live and taking it live included).
  final Duration timeout;

  final _changes = StreamController<void>.broadcast();
  final _pending = <String, Completer<YouTubeResult>>{};
  final _ids = const Uuid();
  YouTubeStatus? _status;
  String? _statusJson;

  /// The Camera's YouTube state; null from a Camera without it (older, or not in broadcast mode).
  YouTubeStatus? get status => _status;

  /// The Camera can use a YouTube account.
  bool get available => _status?.accountAvailable ?? false;

  /// A new state from a status or a command's answer; [changes] fires only when it differs.
  void update(YouTubeStatus? status) {
    final json = status == null ? null : jsonEncode(status.toJson());
    if (json == _statusJson) return;
    _status = status;
    _statusJson = json;
    if (!_changes.isClosed) _changes.add(null);
  }

  /// A message from the Camera: answers to this viewer's commands.
  void onMessage(WsMessage m) {
    if (m case YouTubeResult(:final requestId)) {
      final waiting = _pending.remove(requestId);
      if (waiting == null) return;
      if (m.status case final s?) update(s);
      waiting.complete(m);
    }
  }

  /// The link to the Camera is gone or replaced: commands in flight will not be answered.
  void linkChanged() {
    for (final c in _pending.values) {
      c.completeError(const YouTubeAccountException('no_camera'));
    }
    _pending.clear();
  }

  /// Sends [action] to the Camera and waits for its answer. Throws [YouTubeAccountException]
  /// with the Camera's code, or `no_camera` when it cannot be reached or does not answer.
  Future<YouTubeResult> command(YouTubeAction action, {String? title, String? description, YouTubePrivacy? privacy}) async {
    final id = _ids.v4();
    final done = _pending[id] = Completer<YouTubeResult>();
    final cmd = YouTubeCmd(requestId: id, action: action, title: title, description: description, privacy: privacy?.name);
    if (!_send(cmd)) {
      _pending.remove(id);
      throw const YouTubeAccountException('no_camera');
    }
    final YouTubeResult result;
    try {
      result = await done.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw const YouTubeAccountException('no_camera');
    }
    if (result.errorCode case final code?) throw YouTubeAccountException(code, result.errorMessage);
    return result;
  }

  @override
  String? get email => _status?.email;

  @override
  YouTubeChannel? get channel => switch (_status) {
        YouTubeStatus(:final channelId?, :final channelTitle?) when email != null =>
          YouTubeChannel(id: channelId, title: channelTitle),
        _ => null,
      };

  @override
  YouTubeBroadcast? get current => switch (_status?.live) {
        final l? => YouTubeBroadcast(
            id: l.id,
            title: l.title,
            description: l.description,
            privacy: YouTubePrivacy.values.asNameMap()[l.privacy] ?? YouTubePrivacy.unlisted,
            lifeCycle: YouTubeLifeCycle.values.asNameMap()[l.lifeCycle] ?? YouTubeLifeCycle.other,
            scheduledStartTime: null,
          ),
        null => null,
      };

  @override
  Stream<void> get changes => _changes.stream;

  /// The Camera decides: true while it streams to its account.
  @override
  bool get active => _status?.destination == YouTubeDestination.account;

  /// Saving a stream key here asks the Camera to use its key (ignored there while signed in).
  @override
  Future<void> setActive(bool active) async {
    if (active || _status?.destination != YouTubeDestination.account || email != null) return;
    try {
      await command(YouTubeAction.useKey);
    } on YouTubeAccountException {
      // The key is saved anyway; the Camera's checklist still says where it streams.
    }
  }

  @override
  Future<void> restore() async {}

  /// Sign-in happens on the Camera, never on a viewer.
  @override
  Future<void> signIn() => throw UnsupportedError('Sign in on the Camera');

  /// Sign-out happens on the Camera, never on a viewer.
  @override
  Future<void> signOut() => throw UnsupportedError('Sign out on the Camera');

  @override
  Future<YouTubeBroadcast?> refresh() async {
    await command(YouTubeAction.refresh);
    return current;
  }

  @override
  Future<YouTubeTarget> save({
    required String title,
    required String description,
    required YouTubePrivacy privacy,
    bool fresh = false,
  }) async =>
      _target(await command(
        fresh ? YouTubeAction.create : YouTubeAction.save,
        title: title,
        description: description,
        privacy: privacy,
      ));

  @override
  Future<YouTubeIngest?> ingest() async => switch (_status?.ingest) {
        final i? => YouTubeIngest.values.asNameMap()[i],
        null => null,
      };

  @override
  Future<YouTubeTarget> ensureLive({required String defaultTitle}) async =>
      _target(await command(YouTubeAction.prepare));

  YouTubeTarget _target(YouTubeResult r) {
    final live = current;
    if (live == null) throw const YouTubeAccountException('api', 'No live');
    return (server: r.server ?? BroadcastInfo.defaultServer, key: '', broadcast: live);
  }

  @override
  void dispose() {
    linkChanged();
    unawaited(_changes.close());
  }
}

/// The Camera's YouTube account for this viewer; one object for the whole session, so screens
/// that hold it keep working across reconnections.
final viewerYouTubeAccountProvider = Provider.autoDispose<RemoteYouTubeAccount>((ref) {
  final account = RemoteYouTubeAccount(send: (m) => ref.read(sessionLinkProvider)?.send(m) ?? false);
  StreamSubscription<WsMessage>? sub;
  ref.listen<SessionLink?>(sessionLinkProvider, (_, link) {
    unawaited(sub?.cancel());
    account.linkChanged();
    sub = link?.messages.listen(account.onMessage);
  }, fireImmediately: true);
  ref.listen(linkStateProvider.select((s) => s?.status?.youtube), (_, y) => account.update(y), fireImmediately: true);
  ref.onDispose(() {
    unawaited(sub?.cancel());
    account.dispose();
  });
  return account;
});

/// The Camera's YouTube state, rebuilt only when it changes; null from a Camera without it.
final viewerYouTubeStatusProvider = StreamProvider.autoDispose<YouTubeStatus?>((ref) async* {
  final account = ref.watch(viewerYouTubeAccountProvider);
  yield account.status;
  yield* account.changes.map((_) => account.status);
});
