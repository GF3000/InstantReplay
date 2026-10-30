import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/data/viewer_api.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late List<http.Request> requests;

  Future<ProviderContainer> container({
    required Future<http.Response> Function(http.Request) handler,
    Uri? page,
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    requests = [];
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      pageUriProvider.overrideWithValue(page),
      viewerHttpClientProvider.overrideWithValue(MockClient((r) {
        requests.add(r);
        return handler(r);
      })),
    ]);
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the whole test.
    c.listen(viewerSetupProvider, (_, _) {});
    return c;
  }

  Future<http.Response> okToken(http.Request r) async {
    if (r.url.path == Api.pair && jsonDecode(r.body)['code'] == '123456') {
      return http.Response(jsonEncode(const PairResponse(token: 'tok').toJson()), 200);
    }
    return http.Response('', 401);
  }

  test('normalizes typed camera addresses', () {
    expect(normalizeCameraAddress('192.168.1.20'), Uri.parse('http://192.168.1.20:8080'));
    expect(normalizeCameraAddress(' http://10.0.0.2:9000/x?y=1 '), Uri.parse('http://10.0.0.2:9000'));
    expect(normalizeCameraAddress('ftp://x'), isNull);
    expect(normalizeCameraAddress(''), isNull);
  });

  group('scanned QR', () {
    test("the camera's QR gives its address and token", () {
      final link = parseScannedCameraLink('http://192.168.43.1:8080/?k=abc123');
      expect(link?.base, Uri.parse('http://192.168.43.1:8080'));
      expect(link?.token, 'abc123');
      expect(parseScannedCameraLink(' http://10.0.0.2:9000 ')?.base, Uri.parse('http://10.0.0.2:9000'));
    });

    test('without a token: address only', () {
      expect(parseScannedCameraLink('http://192.168.43.1:8080/'), (base: Uri.parse('http://192.168.43.1:8080'), token: null));
      expect(parseScannedCameraLink('http://192.168.43.1:8080/?k=')?.token, isNull);
    });

    test('other sites are not camera links', () {
      expect(parseScannedCameraLink('https://example.com/?k=abc'), isNull);
      expect(parseScannedCameraLink('http://example.com/menu'), isNull);
      expect(parseScannedCameraLink('http://192.168.43.1/?k=abc'), isNull); // no port
      expect(parseScannedCameraLink('http://192.168.43.1:8080/clips?k=abc'), isNull);
      expect(parseScannedCameraLink('http://192.168.43.1:8080/?k=abc&utm=x'), isNull);
    });

    test('garbage is not a camera link', () {
      expect(parseScannedCameraLink(''), isNull);
      expect(parseScannedCameraLink('hello'), isNull);
      expect(parseScannedCameraLink('WIFI:S:Pitch;T:WPA;P:secret;;'), isNull);
      expect(parseScannedCameraLink('192.168.43.1:8080'), isNull);
      expect(parseScannedCameraLink('http://[bad'), isNull);
    });

    test('web reads its page address with the same parser', () {
      expect(parseCameraLink(Uri.parse('http://192.168.43.1:8080/?k=t#/viewer')),
          (base: Uri.parse('http://192.168.43.1:8080'), token: 't'));
      expect(parseCameraLink(Uri.parse('http://localhost:5000/?camera=http://10.0.0.2:8080'))?.base,
          Uri.parse('http://10.0.0.2:8080'));
    });
  });

  test('Android: a scanned link with a token pairs at once; without one, asks for the code', () async {
    final c = await container(handler: okToken);
    final setup = c.read(viewerSetupProvider.notifier);
    await setup.connectTo(parseScannedCameraLink('http://192.168.43.1:8080/?k=qr')!);
    expect(c.read(viewerSetupProvider).paired, isTrue);
    expect(c.read(viewerSetupProvider).token, 'qr');
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('viewer.lastCamera'), 'http://192.168.43.1:8080');
    expect(prefs.getString('viewer.token.http://192.168.43.1:8080'), 'qr');

    await setup.changeCamera();
    await setup.connectTo(parseScannedCameraLink('http://10.0.0.2:8080')!);
    expect(c.read(viewerSetupProvider).base, Uri.parse('http://10.0.0.2:8080'));
    expect(c.read(viewerSetupProvider).paired, isFalse);
    expect(requests, isEmpty);
  });

  test('Android: address, then code → token persisted per camera', () async {
    final c = await container(handler: okToken);
    final setup = c.read(viewerSetupProvider.notifier);
    expect(c.read(viewerSetupProvider).base, isNull);

    expect(await setup.setAddress('nope://'), isFalse);
    expect(c.read(viewerSetupProvider).error, PairError.invalidAddress);

    expect(await setup.setAddress('192.168.1.20:8080'), isTrue);
    expect(c.read(viewerSetupProvider).base, Uri.parse('http://192.168.1.20:8080'));
    expect(c.read(viewerSetupProvider).paired, isFalse);

    expect(await setup.pair('123456'), isTrue);
    expect(c.read(viewerSetupProvider).token, 'tok');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.toString(), 'http://192.168.1.20:8080${Api.pair}');
    expect(jsonDecode(requests.single.body), {'code': '123456'});

    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString('viewer.token.http://192.168.1.20:8080'), 'tok');
    expect(prefs.getString('viewer.lastCamera'), 'http://192.168.1.20:8080');

    // The API now authenticates with the token.
    expect(c.read(viewerApiProvider)?.token, 'tok');
    expect(c.read(viewerApiProvider)?.wsUri.toString(), 'ws://192.168.1.20:8080${Api.ws}?k=tok');
  });

  test('a restored camera reuses its saved token', () async {
    final c = await container(handler: okToken, saved: {
      'viewer.lastCamera': 'http://192.168.1.20:8080',
      'viewer.token.http://192.168.1.20:8080': 'saved',
    });
    expect(c.read(viewerSetupProvider).token, 'saved');
    expect(requests, isEmpty);
  });

  test('pairing errors: wrong code, rate limit, unreachable', () async {
    var status = 401;
    var throwNetwork = false;
    final c = await container(handler: (r) async {
      if (throwNetwork) throw const SocketException('down');
      return http.Response('', status);
    });
    final setup = c.read(viewerSetupProvider.notifier);
    await setup.setAddress('10.0.0.2');

    expect(await setup.pair('000000'), isFalse);
    expect(c.read(viewerSetupProvider).error, PairError.wrongCode);
    expect(c.read(viewerSetupProvider).busy, isFalse);

    status = 429;
    await setup.pair('000000');
    expect(c.read(viewerSetupProvider).error, PairError.tooManyAttempts);

    throwNetwork = true;
    await setup.pair('000000');
    expect(c.read(viewerSetupProvider).error, PairError.unreachable);
    expect(c.read(viewerSetupProvider).token, isNull);
  });

  test('web: the page origin is the camera and ?k= from the QR is used and saved', () async {
    final c = await container(handler: okToken, page: Uri.parse('http://192.168.43.1:8080/?k=fromqr#/viewer'));
    final s = c.read(viewerSetupProvider);
    expect(s.addressFixed, isTrue);
    expect(s.base, Uri.parse('http://192.168.43.1:8080'));
    expect(s.token, 'fromqr');
    expect(c.read(sharedPreferencesProvider).getString('viewer.token.http://192.168.43.1:8080'), 'fromqr');
    expect(requests, isEmpty);
  });

  test('web without ?k= asks for the code; a rejected token is forgotten', () async {
    final c = await container(handler: okToken, page: Uri.parse('http://192.168.43.1:8080/#/viewer'));
    expect(c.read(viewerSetupProvider).token, isNull);
    await c.read(viewerSetupProvider.notifier).pair('123456');
    expect(c.read(viewerSetupProvider).token, 'tok');

    await c.read(viewerSetupProvider.notifier).forgetToken(expired: true);
    expect(c.read(viewerSetupProvider).token, isNull);
    expect(c.read(viewerSetupProvider).error, PairError.sessionExpired);
    expect(c.read(sharedPreferencesProvider).getString('viewer.token.http://192.168.43.1:8080'), isNull);
  });

  test('viewer id is stable per install', () async {
    final c = await container(handler: okToken);
    final id = c.read(viewerIdProvider);
    expect(id, hasLength(36));
    expect(c.read(sharedPreferencesProvider).getString('viewer.id'), id);
  });

  test('API sends the token as a Bearer header', () async {
    final seen = <http.BaseRequest>[];
    final api = ViewerApi(
      client: MockClient((r) async {
        seen.add(r);
        return http.Response(jsonEncode(const CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Cam').toJson()), 200);
      }),
      base: Uri.parse('http://h:8080'),
      token: 'tok',
    );
    expect((await api.info()).name, 'Cam');
    expect(seen.single.headers['Authorization'], 'Bearer tok');
  });
}
