import 'dart:convert';

import 'package:http/http.dart' as http;

/// Who can watch a YouTube live.
enum YouTubePrivacy { public, unlisted, private }

/// Where a YouTube live is in its life (`status.lifeCycleStatus`), reduced to what the app shows.
enum YouTubeLifeCycle {
  /// Created or ready: starts by itself once the stream arrives (auto-start).
  ready,

  /// Testing or starting: YouTube got the stream and is about to go public.
  starting,
  live,
  complete,

  /// Revoked or anything unknown.
  other;

  static YouTubeLifeCycle parse(String? s) => switch (s) {
        'created' || 'ready' => ready,
        'testStarting' || 'testing' || 'liveStarting' => starting,
        'live' => live,
        'complete' => complete,
        _ => other,
      };

  /// A live that can still be used: not finished.
  bool get usable => this == ready || this == starting || this == live;
}

/// Whether YouTube is receiving the stream (`liveStreams.status`).
enum YouTubeIngest {
  /// Receiving, healthy (`good` / `ok`).
  good,

  /// Receiving with problems (`bad`).
  bad,

  /// Not receiving anything.
  none;

  static YouTubeIngest parse(String? streamStatus, String? health) {
    if (streamStatus != 'active') return none;
    return switch (health) {
      'bad' => bad,
      'noData' => none,
      _ => good,
    };
  }
}

/// A YouTube live (`liveBroadcast`) as the app uses it.
class YouTubeBroadcast {
  const YouTubeBroadcast({
    required this.id,
    required this.title,
    required this.description,
    required this.privacy,
    required this.lifeCycle,
    required this.scheduledStartTime,
    this.boundStreamId,
  });

  factory YouTubeBroadcast.fromJson(Map<String, Object?> json) {
    final snippet = (json['snippet'] as Map?)?.cast<String, Object?>() ?? const {};
    final status = (json['status'] as Map?)?.cast<String, Object?>() ?? const {};
    final details = (json['contentDetails'] as Map?)?.cast<String, Object?>() ?? const {};
    return YouTubeBroadcast(
      id: json['id']! as String,
      title: snippet['title'] as String? ?? '',
      description: snippet['description'] as String? ?? '',
      privacy: YouTubePrivacy.values.asNameMap()[status['privacyStatus']] ?? YouTubePrivacy.unlisted,
      lifeCycle: YouTubeLifeCycle.parse(status['lifeCycleStatus'] as String?),
      scheduledStartTime: snippet['scheduledStartTime'] as String?,
      boundStreamId: details['boundStreamId'] as String?,
    );
  }

  final String id;
  final String title;
  final String description;
  final YouTubePrivacy privacy;
  final YouTubeLifeCycle lifeCycle;
  final String? scheduledStartTime;
  final String? boundStreamId;

  /// The watch page.
  String get url => 'https://youtu.be/$id';
}

/// A YouTube stream (`liveStream`): where the Camera sends its RTMP.
class YouTubeStream {
  const YouTubeStream({required this.id, required this.server, required this.key, required this.ingest});

  factory YouTubeStream.fromJson(Map<String, Object?> json) {
    final cdn = (json['cdn'] as Map?)?.cast<String, Object?>() ?? const {};
    final ingestion = (cdn['ingestionInfo'] as Map?)?.cast<String, Object?>() ?? const {};
    final status = (json['status'] as Map?)?.cast<String, Object?>() ?? const {};
    final health = (status['healthStatus'] as Map?)?.cast<String, Object?>() ?? const {};
    return YouTubeStream(
      id: json['id']! as String,
      server: ingestion['ingestionAddress'] as String? ?? '',
      key: ingestion['streamName'] as String? ?? '',
      ingest: YouTubeIngest.parse(status['streamStatus'] as String?, health['status'] as String?),
    );
  }

  final String id;
  final String server;
  final String key;
  final YouTubeIngest ingest;
}

/// A YouTube API call that failed. [reason] is YouTube's error reason when it gave one (for
/// example `liveStreamingNotEnabled`), else the HTTP status.
class YouTubeApiException implements Exception {
  const YouTubeApiException(this.status, this.reason, [this.message]);

  final int status;
  final String reason;
  final String? message;

  @override
  String toString() => 'YouTube $status $reason${message == null ? '' : ': $message'}';
}

/// The few YouTube Data API v3 calls the app needs to run a live (SPEC §12.1): one reusable
/// stream per account (its key stays the same, so the Camera can keep it), and one broadcast per
/// match that starts and ends by itself with the stream.
///
/// Quota: inserts, binds and updates cost about 50 units each, reads 1. A match is about 200.
class YouTubeApi {
  YouTubeApi({required this.client, required this.token});

  final http.Client client;

  /// A valid access token for the `youtube` scope; [refresh] true after a 401, for a new one.
  final Future<String> Function({bool refresh}) token;

  static const _base = 'https://www.googleapis.com/youtube/v3';

  /// Our own stream [id], or null when it no longer exists.
  Future<YouTubeStream?> stream(String id) async {
    final json = await _call('GET', '/liveStreams', {'part': 'id,cdn,status', 'id': id});
    final items = (json['items'] as List?) ?? const [];
    return items.isEmpty ? null : YouTubeStream.fromJson((items.first as Map).cast());
  }

  /// A new reusable RTMP stream with a variable resolution and frame rate.
  Future<YouTubeStream> createStream(String title) async {
    final json = await _call('POST', '/liveStreams', {
      'part': 'id,snippet,cdn,contentDetails,status',
    }, {
      'snippet': {'title': title},
      'cdn': {'ingestionType': 'rtmp', 'resolution': 'variable', 'frameRate': 'variable'},
      'contentDetails': {'isReusable': true},
    });
    return YouTubeStream.fromJson(json);
  }

  Future<YouTubeBroadcast?> broadcast(String id) async {
    final json = await _call('GET', '/liveBroadcasts', {'part': 'id,snippet,status,contentDetails', 'id': id});
    final items = (json['items'] as List?) ?? const [];
    return items.isEmpty ? null : YouTubeBroadcast.fromJson((items.first as Map).cast());
  }

  /// A new live that goes public as soon as the stream arrives and ends when it stops.
  Future<YouTubeBroadcast> createBroadcast({
    required String title,
    required String description,
    required YouTubePrivacy privacy,
    required DateTime start,
  }) async {
    final json = await _call('POST', '/liveBroadcasts', {
      'part': 'id,snippet,status,contentDetails',
    }, {
      'snippet': {'title': title, 'description': description, 'scheduledStartTime': start.toUtc().toIso8601String()},
      'status': {'privacyStatus': privacy.name, 'selfDeclaredMadeForKids': false},
      'contentDetails': {'enableAutoStart': true, 'enableAutoStop': true, 'enableDvr': true},
    });
    return YouTubeBroadcast.fromJson(json);
  }

  Future<void> bind(String broadcastId, String streamId) =>
      _call('POST', '/liveBroadcasts/bind', {'part': 'id,contentDetails', 'id': broadcastId, 'streamId': streamId});

  /// Changes the title, description and privacy of [current], also while it is live.
  Future<YouTubeBroadcast> updateBroadcast(
    YouTubeBroadcast current, {
    required String title,
    required String description,
    required YouTubePrivacy privacy,
  }) async {
    final json = await _call('PUT', '/liveBroadcasts', {
      'part': 'id,snippet,status',
    }, {
      'id': current.id,
      'snippet': {
        'title': title,
        'description': description,
        // Required by update; unchanged.
        'scheduledStartTime': ?current.scheduledStartTime,
      },
      'status': {'privacyStatus': privacy.name},
    });
    // The update response leaves out contentDetails; keep what we knew.
    final updated = YouTubeBroadcast.fromJson(json);
    return YouTubeBroadcast(
      id: updated.id,
      title: updated.title,
      description: updated.description,
      privacy: updated.privacy,
      lifeCycle: updated.lifeCycle,
      scheduledStartTime: updated.scheduledStartTime,
      boundStreamId: current.boundStreamId,
    );
  }

  Future<Map<String, Object?>> _call(String method, String path, Map<String, String> query,
      [Map<String, Object?>? body]) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    Future<http.Response> send(String bearer) {
      final request = http.Request(method, uri)..headers['Authorization'] = 'Bearer $bearer';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode(body);
      }
      return client.send(request).then(http.Response.fromStream);
    }

    var response = await send(await token());
    if (response.statusCode == 401) response = await send(await token(refresh: true));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const {};
      return (jsonDecode(response.body) as Map).cast<String, Object?>();
    }
    throw _error(response);
  }

  static YouTubeApiException _error(http.Response response) {
    try {
      final error = ((jsonDecode(response.body) as Map)['error'] as Map).cast<String, Object?>();
      final errors = (error['errors'] as List?) ?? const [];
      final reason = errors.isEmpty ? null : (errors.first as Map)['reason'] as String?;
      return YouTubeApiException(response.statusCode, reason ?? '${response.statusCode}', error['message'] as String?);
    } catch (_) {
      return YouTubeApiException(response.statusCode, '${response.statusCode}');
    }
  }
}
