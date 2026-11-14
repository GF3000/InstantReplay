/// YouTube through the Camera (SPEC §12.1): the YouTube account lives on the Camera (Google
/// sign-in happens there), and viewers see its state in `status.youtube` and change it with
/// `youtube_cmd`. Viewers never talk to YouTube themselves.
library;

import 'models.dart';

/// Where the Camera's stream goes.
enum YouTubeDestination {
  /// No stream key and no account: nothing to stream to yet.
  none,

  /// A stream key pasted by hand.
  key,

  /// A live of the YouTube account signed in on the Camera. The account wins over a key while
  /// signed in; also reported signed out when the last session was signed in and is not back yet
  /// (going live then needs a sign-in on the Camera, or a key).
  account;

  static YouTubeDestination parse(Object? v) =>
      YouTubeDestination.values.firstWhere((d) => d.name == v, orElse: () => none);
}

/// What viewers can ask the Camera to do with its YouTube account ([YouTubeCmd]).
enum YouTubeAction {
  /// Update the current live with title, description and privacy (or create one when there is
  /// none that can still be used).
  save,

  /// Create a new live with title, description and privacy.
  create,

  /// Make sure a live is there for the stream (the current one, or a new one titled by the
  /// Camera); its link comes back in the status.
  prepare,

  /// Read the current live and whether YouTube receives the stream again.
  refresh,

  /// Stream with the stored key from now on (ignored by the Camera while it is signed in: signing
  /// out there is the way back to the key).
  useKey;

  static YouTubeAction? parse(Object? v) => YouTubeAction.values.where((a) => a.name == v).firstOrNull;
}

/// The live the Camera's account created last, as last read (it may be finished).
class YouTubeLiveInfo {
  const YouTubeLiveInfo({
    required this.id,
    required this.title,
    this.description = '',
    required this.privacy,
    required this.lifeCycle,
    required this.url,
  });

  factory YouTubeLiveInfo.fromJson(Json j) => YouTubeLiveInfo(
        id: j['id']! as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        privacy: j['privacy'] as String? ?? 'unlisted',
        lifeCycle: j['lifeCycle'] as String? ?? 'other',
        url: j['url'] as String? ?? '',
      );

  final String id;
  final String title;
  final String description;

  /// `public`, `unlisted` or `private`.
  final String privacy;

  /// `ready`, `starting`, `live`, `complete` or `other`.
  final String lifeCycle;

  /// The watch page.
  final String url;

  Json toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'privacy': privacy,
        'lifeCycle': lifeCycle,
        'url': url,
      };
}

/// The Camera's YouTube state as viewers see it (`status.youtube`, broadcast mode only). Never
/// carries the stream key.
class YouTubeStatus {
  const YouTubeStatus({
    required this.destination,
    this.accountAvailable = true,
    this.email,
    this.channelId,
    this.channelTitle,
    this.live,
    this.ingest,
    this.errorCode,
    this.errorMessage,
  });

  factory YouTubeStatus.fromJson(Json j) => YouTubeStatus(
        destination: YouTubeDestination.parse(j['destination']),
        accountAvailable: j['accountAvailable'] as bool? ?? false,
        email: j['email'] as String?,
        channelId: j['channelId'] as String?,
        channelTitle: j['channelTitle'] as String?,
        live: switch (j['live']) {
          final Json l => YouTubeLiveInfo.fromJson(l),
          _ => null,
        },
        ingest: j['ingest'] as String?,
        errorCode: j['errorCode'] as String?,
        errorMessage: j['errorMessage'] as String?,
      );

  final YouTubeDestination destination;

  /// The Camera can sign in to a YouTube account (Google sign-in is set up there).
  final bool accountAvailable;

  /// The account signed in on the Camera; null when signed out.
  final String? email;

  /// The channel the sign-in acts for; null while unknown (show [email] then).
  final String? channelId;
  final String? channelTitle;

  /// The live the account created last; null without one.
  final YouTubeLiveInfo? live;

  /// Whether YouTube receives the stream (`good`, `bad`, `none`), as of the last refresh; null
  /// when unknown.
  final String? ingest;

  /// The last failed account action on the Camera (from any viewer or the Camera itself), with
  /// the same codes as [YouTubeResult.errorCode]; null after a success.
  final String? errorCode;
  final String? errorMessage;

  bool get signedIn => email != null;

  Json toJson() => {
        'destination': destination.name,
        'accountAvailable': accountAvailable,
        if (email != null) 'email': email,
        if (channelId != null) 'channelId': channelId,
        if (channelTitle != null) 'channelTitle': channelTitle,
        if (live != null) 'live': live!.toJson(),
        if (ingest != null) 'ingest': ingest,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };
}

