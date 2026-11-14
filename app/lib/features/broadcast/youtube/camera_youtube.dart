import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:replay_protocol/replay_protocol.dart';

import '../broadcast_controller.dart';
import '../broadcast_host.dart';
import 'youtube_account.dart';
import 'youtube_api.dart';

/// The Camera's YouTube account as viewers reach it (SPEC §12.1): the account lives on the Camera
/// (Google sign-in happens there), viewers see [status] in `status.youtube` and change it with
/// `youtube_cmd`, which runs here with the account. Viewers never call YouTube.
///
/// Also makes sure a live is there before a viewer's Go live ([prepareStart]), as the Camera's
/// own Go live does, and reads the current live once per sign-in so its link is known early
/// (a refresh only: showing a screen never creates a live).
class CameraYouTube {
  CameraYouTube({required this.account, required this.stream, required this.defaultTitle}) {
    _subs
      ..add(account.changes.listen((_) => _onAccountChanged()))
      ..add(stream.stateChanges.listen((_) => _notify()));
    _onAccountChanged();
  }

  final YouTubeAccount account;
  final BroadcastController stream;

  /// The title of a live created without one (`Match 14/11/2026`).
  final String Function() defaultTitle;

  final _changes = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  YouTubeIngest? _ingest;
  YouTubeAccountException? _error;
  String? _signedInAs;

  /// Fires when [status] may have changed.
  Stream<void> get changes => _changes.stream;

  /// What viewers see. Never the key.
  YouTubeStatus get status {
    final live = account.current;
    final channel = account.email == null ? null : account.channel;
    return YouTubeStatus(
      destination: account.active
          ? YouTubeDestination.account
          : stream.configured
              ? YouTubeDestination.key
              : YouTubeDestination.none,
      email: account.email,
      channelId: channel?.id,
      channelTitle: channel?.title,
      live: live == null
          ? null
          : YouTubeLiveInfo(
              id: live.id,
              title: live.title,
              description: live.description,
              privacy: live.privacy.name,
              lifeCycle: live.lifeCycle.name,
              url: live.url,
            ),
      ingest: account.email == null ? null : _ingest?.name,
      errorCode: _error?.code,
      errorMessage: _error?.message,
    );
  }

  /// Runs a viewer's command with the account. Returns the ingest server the Camera streams to
  /// after `save`, `create` and `prepare` (the key stays here). Throws [YouTubeAccountException].
  Future<String?> run(YouTubeCmd command) => _guard(() async {
        switch (command.action) {
          case YouTubeAction.useKey:
            await account.setActive(false);
            return null;
          case YouTubeAction.refresh:
            _signedIn();
            await account.refresh();
            _ingest = await account.ingest();
            return null;
          case YouTubeAction.prepare:
            _signedIn();
            return _use(await account.ensureLive(defaultTitle: defaultTitle()));
          case YouTubeAction.save || YouTubeAction.create:
            _signedIn();
            final title = command.title?.trim() ?? '';
            return _use(await account.save(
              title: title.isEmpty ? defaultTitle() : title,
              description: command.description?.trim() ?? '',
              privacy: YouTubePrivacy.values.asNameMap()[command.privacy] ??
                  account.current?.privacy ??
                  YouTubePrivacy.unlisted,
              fresh: command.action == YouTubeAction.create,
            ));
        }
      });

  /// Before a viewer's Go live: in account mode a live must be there to receive the stream, and
  /// the Camera must stream to the account's key. Nothing with a stream key. Throws
  /// [BroadcastException] `youtube_<code>` (`youtube_not_signed_in` when the account mode has
  /// no session).
  Future<void> prepareStart() async {
    if (!account.active) return;
    try {
      await _guard(() async {
        _signedIn();
        await _use(await account.ensureLive(defaultTitle: defaultTitle()));
      });
    } on YouTubeAccountException catch (e) {
      throw BroadcastException('youtube_${e.code}', e.message);
    }
  }

  void _signedIn() {
    if (account.email == null) throw const YouTubeAccountException('not_signed_in');
  }

  /// Streams to [target] from now on (its key is the account's reusable stream's).
  Future<String> _use(YouTubeTarget target) async {
    await stream.configure(
      server: target.server,
      key: target.key,
      targetKbps: stream.targetKbps,
      audio: stream.audio,
    );
    return target.server;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      _error = null;
      _notify();
      return result;
    } on YouTubeAccountException catch (e) {
      _error = e;
      _notify();
      rethrow;
    } catch (e) {
      final error = _error = YouTubeAccountException('api', '$e');
      _notify();
      throw error;
    }
  }

  /// A new session (sign-in, restore, other account) starts clean and reads its current live
  /// once, so "Share the live" knows the link early. Only a read: never creates a live, and a
  /// failure is not retried here (sharing or going live asks again).
  void _onAccountChanged() {
    final email = account.email;
    if (email != _signedInAs) {
      _signedInAs = email;
      _error = null;
      _ingest = null;
      if (email != null && account.current != null) {
        unawaited(account.refresh().then((_) {}, onError: (Object e) => debugPrint('IR-YT read live failed: $e')));
      }
    }
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_changes.close());
  }
}
