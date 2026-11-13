import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_account.dart';
import 'package:instant_replay/features/broadcast/youtube/youtube_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny YouTube: one reusable stream, broadcasts whose life cycle the test sets.
class _FakeYouTube {
  final calls = <String>[];
  final lifeCycle = <String, String>{};
  final bound = <String, String>{};
  var nextId = 0;

  /// The Camera is already streaming to the account's key.
  var receiving = false;

  /// Transitions YouTube refuses (lives made with the monitor stream on can't skip testing).
  final refuse = <String>{};

  Map<String, Object?> get _stream => {
        'id': 's1',
        'cdn': {
          'ingestionInfo': {'ingestionAddress': 'rtmp://yt/live2', 'streamName': 'key-s1'},
        },
        'status': {
          'streamStatus': receiving ? 'active' : 'inactive',
          'healthStatus': {'status': receiving ? 'good' : 'noData'},
        },
      };

  Map<String, Object?> _broadcast(String id) => {
        'id': id,
        'snippet': {'title': 'T $id', 'description': '', 'scheduledStartTime': 'S'},
        'status': {'privacyStatus': 'unlisted', 'lifeCycleStatus': lifeCycle[id]},
        'contentDetails': {'boundStreamId': ?bound[id]},
      };

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/youtube/v3', '');
    calls.add('${r.method} $path');
    http.Response json(Object body) => http.Response(jsonEncode(body), 200);
    final id = r.url.queryParameters['id'];
    switch ((r.method, path)) {
      case ('GET', '/liveStreams'):
        return json({
          'items': [_stream],
        });
      case ('POST', '/liveStreams'):
        return json(_stream);
      case ('GET', '/liveBroadcasts'):
        return json({
          'items': [if (lifeCycle.containsKey(id)) _broadcast(id!)],
        });
      case ('POST', '/liveBroadcasts'):
        final created = 'b${++nextId}';
        lifeCycle[created] = 'created';
        return json(_broadcast(created));
      case ('POST', '/liveBroadcasts/bind'):
        bound[id!] = r.url.queryParameters['streamId']!;
        return json({'id': id});
      case ('POST', '/liveBroadcasts/transition'):
        final to = r.url.queryParameters['broadcastStatus']!;
        if (refuse.contains(to)) {
          return http.Response(
              jsonEncode({
                'error': {
                  'code': 403,
                  'errors': [
                    {'reason': 'invalidTransition'},
                  ],
                },
              }),
              403);
        }
        lifeCycle[id!] = to;
        return json(_broadcast(id));
      case ('PUT', '/liveBroadcasts'):
        return json(_broadcast((jsonDecode(r.body) as Map)['id'] as String));
    }
    return http.Response('', 404);
  }
}

void main() {
  late SharedPreferences prefs;
  late _FakeYouTube yt;

  GoogleYouTubeAccount account() =>
      GoogleYouTubeAccount.signedIn(prefs: prefs, client: MockClient(yt.handle), email: 'coach@example.com');

  setUp(() async {
    GoogleYouTubeAccount.transitionPause = Duration.zero;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    yt = _FakeYouTube();
  });

  test('save creates and binds a live, and turns account mode on', () async {
    final a = account();
    expect(a.active, isFalse);
    final target = await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    expect(target.key, 'key-s1');
    expect(target.server, 'rtmp://yt/live2');
    expect(yt.bound['b1'], 's1');
    expect(a.active, isTrue);
    expect(a.current!.id, 'b1');
  });

  test('ensureLive reuses a live that has not ended, without changing it', () async {
    final a = account();
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    yt.calls.clear();
    final target = await a.ensureLive(defaultTitle: 'Match 13/11/2026');
    expect(target.broadcast.id, 'b1');
    expect(yt.calls.where((c) => c.startsWith('POST') || c.startsWith('PUT')), isEmpty);
  });

  test('ensureLive creates the next live once the last one ended with its stream', () async {
    final a = account();
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    yt.lifeCycle['b1'] = 'complete';
    final target = await a.ensureLive(defaultTitle: 'Match 13/11/2026');
    expect(target.broadcast.id, 'b2');
    expect(yt.bound['b2'], 's1');
    expect(target.key, 'key-s1');
    expect(a.current!.id, 'b2');
  });

  test('ensureLive without any live yet creates one', () async {
    final target = await account().ensureLive(defaultTitle: 'Match');
    expect(target.broadcast.id, 'b1');
    expect(yt.bound['b1'], 's1');
  });

  test('a live that is not bound to the stream gets bound', () async {
    final a = account();
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    yt.bound.clear();
    await a.ensureLive(defaultTitle: 'Match');
    expect(yt.bound['b1'], 's1');
  });

  test('saving tells listeners once account mode is on (the stream bar shows the QR at once)', () async {
    final a = account();
    final seen = <bool>[];
    final sub = a.changes.listen((_) => seen.add(a.active));
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.last, isTrue);
  });

  test('account mode is remembered across restarts', () async {
    await account().setActive(true);
    expect(account().active, isTrue);
    await account().setActive(false);
    expect(account().active, isFalse);
  });

  test('a live made while the Camera already streams is taken live (auto start would not fire)', () async {
    yt.receiving = true;
    final target = await account().save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    expect(yt.calls, contains('POST /liveBroadcasts/transition'));
    expect(yt.lifeCycle['b1'], 'live');
    expect(target.broadcast.lifeCycle, YouTubeLifeCycle.live);
  });

  test('without a stream yet the live waits for auto start', () async {
    await account().save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    expect(yt.calls, isNot(contains('POST /liveBroadcasts/transition')));
    expect(yt.lifeCycle['b1'], 'created');
  });

  test('an upcoming live stuck with the stream running is started through testing if needed', () async {
    final a = account();
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    yt.receiving = true;
    yt.refuse.add('live');
    yt.lifeCycle['b1'] = 'ready';
    Future<void>.delayed(Duration.zero, () => yt.refuse.clear());
    final target = await a.ensureLive(defaultTitle: 'Match');
    expect(yt.calls.where((c) => c == 'POST /liveBroadcasts/transition'), hasLength(3));
    expect(target.broadcast.lifeCycle, YouTubeLifeCycle.live);
  });

  test('if YouTube refuses to start it, the live is kept as it was', () async {
    final a = account();
    await a.save(title: 'Final', description: '', privacy: YouTubePrivacy.public, fresh: true);
    yt.receiving = true;
    yt.refuse.addAll(['live', 'testing']);
    final target = await a.ensureLive(defaultTitle: 'Match');
    expect(target.broadcast.id, 'b1');
    expect(target.broadcast.lifeCycle, YouTubeLifeCycle.ready);
  });
}
