import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_account.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_api.dart';

void main() {
  final requests = <http.Request>[];
  late int tokens;

  YouTubeApi api(Future<http.Response> Function(http.Request) handler) {
    requests.clear();
    tokens = 0;
    return YouTubeApi(
      client: MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
      token: ({bool refresh = false}) async => 'token-${++tokens}',
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  test('createBroadcast sends title, privacy and auto start/stop', () async {
    final yt = api((_) async => json({
          'id': 'b1',
          'snippet': {'title': 'Final', 'description': 'd', 'scheduledStartTime': '2026-11-13T10:00:00Z'},
          'status': {'privacyStatus': 'public', 'lifeCycleStatus': 'created'},
          'contentDetails': {'enableAutoStart': true},
        }));
    final b = await yt.createBroadcast(
        title: 'Final', description: 'd', privacy: YouTubePrivacy.public, start: DateTime.utc(2026, 11, 13, 10));
    expect(b.id, 'b1');
    expect(b.lifeCycle, YouTubeLifeCycle.ready);
    expect(b.privacy, YouTubePrivacy.public);
    expect(b.url, 'https://youtu.be/b1');

    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.path, '/youtube/v3/liveBroadcasts');
    expect(r.headers['Authorization'], 'Bearer token-1');
    final body = jsonDecode(r.body) as Map;
    expect(body['snippet']['title'], 'Final');
    expect(body['status'], {'privacyStatus': 'public', 'selfDeclaredMadeForKids': false});
    expect(body['contentDetails']['enableAutoStart'], isTrue);
    expect(body['contentDetails']['enableAutoStop'], isTrue);
  });

  test('createStream returns the RTMP server and key', () async {
    final yt = api((_) async => json({
          'id': 's1',
          'cdn': {
            'ingestionInfo': {'ingestionAddress': 'rtmp://a.rtmp.youtube.com/live2', 'streamName': 'abcd-1234'},
          },
        }));
    final s = await yt.createStream('InstantReplay');
    expect(s.server, 'rtmp://a.rtmp.youtube.com/live2');
    expect(s.key, 'abcd-1234');
    expect((jsonDecode(requests.single.body) as Map)['contentDetails'], {'isReusable': true});
  });

  test('stream health: active+good is good, inactive is none', () async {
    var status = {'streamStatus': 'active', 'healthStatus': {'status': 'good'}};
    final yt = api((_) async => json({
          'items': [
            {'id': 's1', 'status': status},
          ],
        }));
    expect((await yt.stream('s1'))!.ingest, YouTubeIngest.good);
    status = {'streamStatus': 'inactive', 'healthStatus': {'status': 'noData'}};
    expect((await yt.stream('s1'))!.ingest, YouTubeIngest.none);
    expect(YouTubeIngest.parse('active', 'bad'), YouTubeIngest.bad);
  });

  test('a missing broadcast is null', () async {
    final yt = api((_) async => json({'items': <Object>[]}));
    expect(await yt.broadcast('gone'), isNull);
  });

  test('update keeps the scheduled start time and the bound stream', () async {
    final yt = api((_) async => json({
          'id': 'b1',
          'snippet': {'title': 'New', 'description': '', 'scheduledStartTime': 'T'},
          'status': {'privacyStatus': 'unlisted', 'lifeCycleStatus': 'live'},
        }));
    const current = YouTubeBroadcast(
      id: 'b1',
      title: 'Old',
      description: '',
      privacy: YouTubePrivacy.public,
      lifeCycle: YouTubeLifeCycle.live,
      scheduledStartTime: 'T',
      boundStreamId: 's1',
    );
    final b = await yt.updateBroadcast(current, title: 'New', description: '', privacy: YouTubePrivacy.unlisted);
    expect(requests.single.method, 'PUT');
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['snippet']['scheduledStartTime'], 'T');
    expect(body['status'], {'privacyStatus': 'unlisted'});
    expect(b.title, 'New');
    expect(b.boundStreamId, 's1');
    expect(b.lifeCycle, YouTubeLifeCycle.live);
  });

  test('a 401 retries once with a fresh token', () async {
    final yt = api((r) async =>
        r.headers['Authorization'] == 'Bearer token-1' ? http.Response('', 401) : json({'items': <Object>[]}));
    await yt.broadcast('b1');
    expect(requests.map((r) => r.headers['Authorization']), ['Bearer token-1', 'Bearer token-2']);
  });

  test('errors carry YouTube\'s reason, mapped to a UI code', () async {
    final yt = api((_) async => json({
          'error': {
            'code': 403,
            'message': 'Live streaming is not enabled',
            'errors': [
              {'reason': 'liveStreamingNotEnabled'},
            ],
          },
        }, 403));
    final e = await yt.createStream('x').then<YouTubeApiException?>((_) => null, onError: (Object e) => e as YouTubeApiException);
    expect(e!.reason, 'liveStreamingNotEnabled');
    expect(GoogleYouTubeAccount.apiErrorCode(e), 'live_not_enabled');
    expect(GoogleYouTubeAccount.apiErrorCode(const YouTubeApiException(403, 'quotaExceeded')), 'quota');
    expect(GoogleYouTubeAccount.apiErrorCode(const YouTubeApiException(403, 'forbidden')), 'forbidden');
    expect(GoogleYouTubeAccount.apiErrorCode(const YouTubeApiException(500, '500')), 'api');
  });

  test('life cycle: finished lives are not reused', () {
    expect(YouTubeLifeCycle.parse('ready').usable, isTrue);
    expect(YouTubeLifeCycle.parse('testing'), YouTubeLifeCycle.starting);
    expect(YouTubeLifeCycle.parse('live').usable, isTrue);
    expect(YouTubeLifeCycle.parse('complete').usable, isFalse);
    expect(YouTubeLifeCycle.parse('revoked').usable, isFalse);
  });
}
