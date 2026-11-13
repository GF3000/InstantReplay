import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_api.dart';

/// OAuth "web" client of the InstantReplay Google Cloud project, used by Android sign-in as the
/// server client id (no secret involved). Forks signing with another key need their own project.
const googleServerClientId = '105987495571-9265va89r3khtuql057cm6ikkli3ilg4.apps.googleusercontent.com';

const youtubeScope = 'https://www.googleapis.com/auth/youtube';

/// What the Camera needs to stream to a live created with the account.
typedef YouTubeTarget = ({String server, String key, YouTubeBroadcast broadcast});

/// Streaming with a YouTube account instead of a pasted key (SPEC §12.1): sign in with Google,
/// then the app creates the live (title, privacy, auto start and stop), binds it to the account's
/// reusable stream and hands its server and key to the Camera like a manual key.
abstract interface class YouTubeAccount {
  /// The signed-in account's email, or null.
  String? get email;

  /// The live this device created last, as last read (may be finished).
  YouTubeBroadcast? get current;

  /// Fires when [email], [current] or [active] change.
  Stream<void> get changes;

  /// The stream goes to a live of this account (the last save was in account mode), so going on
  /// air must first make sure a live is there to receive it.
  bool get active;

  /// Set from the stream settings: false after saving a manual key.
  Future<void> setActive(bool active);

  /// Restores a previous sign-in without asking. Never throws.
  Future<void> restore();

  /// Asks the user to pick an account and allow YouTube access. Throws [YouTubeAccountException]
  /// (`canceled` when the user backed out).
  Future<void> signIn();

  Future<void> signOut();

  /// Reads [current] again from YouTube; null without one or once deleted.
  Future<YouTubeBroadcast?> refresh();

  /// Updates [current] when it is still usable and [fresh] is false, else creates a new live.
  /// Either way bound to the account's stream, whose server and key are returned.
  Future<YouTubeTarget> save({
    required String title,
    required String description,
    required YouTubePrivacy privacy,
    bool fresh = false,
  });

  /// Whether YouTube is receiving the Camera's stream right now; null when unknown.
  Future<YouTubeIngest?> ingest();

  /// A live ready for the stream: [current] when it can still be used, else a new one (titled
  /// [defaultTitle], with the last visibility). A live ends with its stream, so without this the
  /// next Go live would stream to a key with no live behind it, which YouTube silently drops.
  Future<YouTubeTarget> ensureLive({required String defaultTitle});
}

/// A failed account action, with a code the UI turns into a message: `canceled`,
/// `sign_in_failed`, `not_signed_in`, `live_not_enabled`, `quota`, `forbidden`, `network`, `api`.
class YouTubeAccountException implements Exception {
  const YouTubeAccountException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

/// [YouTubeAccount] with Google Sign-In on Android and the YouTube Data API.
class GoogleYouTubeAccount implements YouTubeAccount {
  GoogleYouTubeAccount({required this._prefs, http.Client? client}) : _client = client ?? http.Client() {
    _api = YouTubeApi(client: _client, token: _token);
    _load();
  }

  /// Signed in as [email] with a fixed token, without Google Sign-In.
  @visibleForTesting
  GoogleYouTubeAccount.signedIn({required this._prefs, required this._client, required String email})
      : _testEmail = email {
    _api = YouTubeApi(client: _client, token: ({bool refresh = false}) async => 'test-token');
    _load();
  }

  void _load() {
    final id = _prefs.getString(_broadcastKey);
    final title = _prefs.getString(_titleKey);
    if (id != null) {
      _current = YouTubeBroadcast(
        id: id,
        title: title ?? '',
        description: _prefs.getString(_descriptionKey) ?? '',
        privacy: YouTubePrivacy.values.asNameMap()[_prefs.getString(_privacyKey)] ?? YouTubePrivacy.unlisted,
        lifeCycle: YouTubeLifeCycle.ready,
        scheduledStartTime: null,
      );
    }
  }

  static const _broadcastKey = 'youtube.broadcast';
  static const _titleKey = 'youtube.title';
  static const _descriptionKey = 'youtube.description';
  static const _privacyKey = 'youtube.privacy';
  static const _activeKey = 'youtube.active';
  static String _streamKey(String email) => 'youtube.stream.$email';

  final SharedPreferences _prefs;
  final http.Client _client;
  late final YouTubeApi _api;
  final _changes = StreamController<void>.broadcast();

  static Future<void>? _init;
  GoogleSignInAccount? _account;
  String? _testEmail;
  String? _accessToken;
  YouTubeBroadcast? _current;

  @override
  String? get email => _account?.email ?? _testEmail;

  @override
  YouTubeBroadcast? get current => _current;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  bool get active => _prefs.getBool(_activeKey) ?? false;

  @override
  Future<void> setActive(bool active) async {
    await _prefs.setBool(_activeKey, active);
    debugPrint('IR-YT account mode ${active ? 'on' : 'off'}');
    _notify();
  }

  static Future<void> _initialize() =>
      _init ??= GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);

  @override
  Future<void> restore() async {
    try {
      await _initialize();
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      debugPrint('IR-YT restore: ${account == null ? 'no session' : 'signed in'}, account mode $active');
      if (account != null) {
        _account = account;
        _notify();
      }
    } catch (e) {
      // Signed out; the user signs in from the dialog.
      debugPrint('IR-YT restore failed: ${e.runtimeType} $e');
    }
  }

  @override
  Future<void> signIn() async {
    try {
      await _initialize();
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const [youtubeScope]);
      final authz = await account.authorizationClient.authorizeScopes(const [youtubeScope]);
      _account = account;
      _accessToken = authz.accessToken;
      debugPrint('IR-YT signed in');
      _notify();
    } on GoogleSignInException catch (e) {
      throw YouTubeAccountException(
        e.code == GoogleSignInExceptionCode.canceled ? 'canceled' : 'sign_in_failed',
        e.description,
      );
    }
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _testEmail = null;
    _accessToken = null;
    _notify();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Signed out locally anyway.
    }
  }

  Future<String> _token({bool refresh = false}) async {
    final account = _account;
    if (account == null) throw const YouTubeAccountException('not_signed_in');
    final client = account.authorizationClient;
    if (refresh && _accessToken != null) {
      await client.clearAuthorizationToken(accessToken: _accessToken!);
      _accessToken = null;
    }
    if (_accessToken case final t?) return t;
    try {
      final authz =
          await client.authorizationForScopes(const [youtubeScope]) ?? await client.authorizeScopes(const [youtubeScope]);
      return _accessToken = authz.accessToken;
    } on GoogleSignInException catch (e) {
      throw YouTubeAccountException(
        e.code == GoogleSignInExceptionCode.canceled ? 'canceled' : 'sign_in_failed',
        e.description,
      );
    }
  }

  @override
  Future<YouTubeBroadcast?> refresh() => _guard(() async {
        final id = _current?.id;
        if (id == null) return null;
        final b = await _api.broadcast(id);
        await _remember(b);
        return b;
      });

  @override
  Future<YouTubeTarget> save({
    required String title,
    required String description,
    required YouTubePrivacy privacy,
    bool fresh = false,
  }) =>
      _guard(() async {
        final stream = await _stream();
        YouTubeBroadcast? broadcast;
        if (!fresh && _current != null) {
          final existing = await _api.broadcast(_current!.id);
          if (existing != null && existing.lifeCycle.usable) {
            broadcast = await _api.updateBroadcast(existing, title: title, description: description, privacy: privacy);
            if (existing.boundStreamId != stream.id) await _api.bind(broadcast.id, stream.id);
          }
        }
        if (broadcast == null) {
          broadcast = await _api.createBroadcast(
            title: title,
            description: description,
            privacy: privacy,
            start: DateTime.now(),
          );
          await _api.bind(broadcast.id, stream.id);
        }
        broadcast = await _startIfReceiving(broadcast, stream);
        await _remember(broadcast);
        await setActive(true);
        return (server: stream.server, key: stream.key, broadcast: broadcast);
      });

  @override
  Future<YouTubeTarget> ensureLive({required String defaultTitle}) async {
    final last = _current;
    final current = last == null ? null : await refresh();
    if (current != null && current.lifeCycle.usable) {
      // Still usable: only make sure it is bound to the stream (a read, plus a bind if needed).
      return _guard(() async {
        final stream = await _stream();
        if (current.boundStreamId != stream.id) await _api.bind(current.id, stream.id);
        final live = await _startIfReceiving(current, stream);
        if (live != current) await _remember(live);
        await setActive(true);
        return (server: stream.server, key: stream.key, broadcast: live);
      });
    }
    return save(
      title: defaultTitle,
      description: '',
      privacy: current?.privacy ?? last?.privacy ?? YouTubePrivacy.unlisted,
      fresh: true,
    );
  }

  /// Auto start only fires when the stream starts after the live was bound. When the Camera was
  /// already streaming (account chosen while on air), the live stays "upcoming" forever and its
  /// link says unavailable; take it live here instead. Best effort: on failure it stays as it was.
  Future<YouTubeBroadcast> _startIfReceiving(YouTubeBroadcast broadcast, YouTubeStream stream) async {
    if (broadcast.lifeCycle != YouTubeLifeCycle.ready || stream.ingest == YouTubeIngest.none) return broadcast;
    try {
      return await _api.transition(broadcast.id, 'live');
    } on YouTubeApiException catch (e) {
      debugPrint('IR-YT go live: ${e.reason}, trying through testing');
    }
    // Lives made with the monitor stream on must pass through testing first.
    try {
      await _api.transition(broadcast.id, 'testing');
      await Future<void>.delayed(transitionPause);
      return await _api.transition(broadcast.id, 'live');
    } on YouTubeApiException catch (e) {
      debugPrint('IR-YT go live failed: ${e.reason}');
      return broadcast;
    }
  }

  /// Between testing and live; YouTube needs a moment to reach testing.
  @visibleForTesting
  static Duration transitionPause = const Duration(seconds: 5);

  @override
  Future<YouTubeIngest?> ingest() async {
    final email = this.email;
    final id = email == null ? null : _prefs.getString(_streamKey(email));
    if (id == null) return null;
    try {
      return (await _api.stream(id))?.ingest;
    } catch (_) {
      return null;
    }
  }

  /// The account's reusable stream, created on first use.
  Future<YouTubeStream> _stream() async {
    final email = this.email;
    if (email == null) throw const YouTubeAccountException('not_signed_in');
    if (_prefs.getString(_streamKey(email)) case final id?) {
      if (await _api.stream(id) case final s? when s.key.isNotEmpty) return s;
    }
    final created = await _api.createStream('InstantReplay');
    await _prefs.setString(_streamKey(email), created.id);
    return created;
  }

  Future<void> _remember(YouTubeBroadcast? b) async {
    _current = b;
    if (b == null) {
      await _prefs.remove(_broadcastKey);
    } else {
      await _prefs.setString(_broadcastKey, b.id);
      await _prefs.setString(_titleKey, b.title);
      await _prefs.setString(_descriptionKey, b.description);
      await _prefs.setString(_privacyKey, b.privacy.name);
    }
    _notify();
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on YouTubeApiException catch (e) {
      throw YouTubeAccountException(apiErrorCode(e), e.message);
    } on http.ClientException catch (e) {
      throw YouTubeAccountException('network', e.message);
    }
  }

  /// The UI code for a YouTube API error.
  static String apiErrorCode(YouTubeApiException e) => switch (e.reason) {
        'liveStreamingNotEnabled' || 'livePermissionBlocked' || 'insufficientLivePermissions' => 'live_not_enabled',
        'quotaExceeded' || 'rateLimitExceeded' || 'userRequestsExceedRateLimit' => 'quota',
        _ when e.status == 401 || e.status == 403 => 'forbidden',
        _ => 'api',
      };

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    unawaited(_changes.close());
    _client.close();
  }
}
