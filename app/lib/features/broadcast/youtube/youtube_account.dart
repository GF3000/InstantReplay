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

  void dispose();
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

