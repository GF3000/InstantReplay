import 'youtube_api.dart';

// The interface only: the Google Sign-In implementation lives in google_youtube_account.dart,
// which the web build never imports, so Google's hosts stay out of the offline web Viewer.

/// What the Camera needs to stream to a live created with the account.
typedef YouTubeTarget = ({String server, String key, YouTubeBroadcast broadcast});

/// Streaming with a YouTube account instead of a pasted key (SPEC §12.1): sign in with Google,
/// then the app creates the live (title, privacy, auto start and stop), binds it to the account's
/// reusable stream and hands its server and key to the Camera like a manual key.
abstract interface class YouTubeAccount {
  /// The signed-in account's email, or null.
  String? get email;

  /// The YouTube channel the sign-in acts for (one Google account can own several), read once
  /// per sign-in or restore. Null while unknown or when it could not be read: show [email].
  YouTubeChannel? get channel;

  /// The live this device created last, as last read (may be finished).
  YouTubeBroadcast? get current;

  /// Fires when [email], [channel], [current] or [active] change.
  Stream<void> get changes;

  /// The stream goes to a live of this account, so going on air must first make sure a live is
  /// there to receive it. The account wins over a stream key: always true while signed in. Also
  /// true signed out when the last session was signed in and is not back yet (going live then
  /// asks to sign in again). Signing out goes back to the stream key.
  bool get active;

  /// Leaves account mode while signed out (saving a stream key does it). Ignored while signed in:
  /// signing out is the way back to the key.
  Future<void> setActive(bool active);

  /// Restores a previous sign-in without asking. Never throws.
  Future<void> restore();

  /// Asks the user to pick an account and allow YouTube access, and switches to account mode.
  /// Throws [YouTubeAccountException] (`canceled` when the user backed out).
  Future<void> signIn();

  /// Signs out and goes back to the stream key.
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

  void dispose();
}

/// How the signed-in account is named on screen: the channel title, else the email.
extension YouTubeAccountName on YouTubeAccount {
  /// The main line: the channel's title, or the email when the channel is unknown.
  String? get displayName => channel?.title ?? email;

  /// The small line under [displayName]: the email, when the channel is known.
  String? get displaySub => channel == null ? null : email;
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

