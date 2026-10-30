import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/discovery/discovered_camera.dart';
import 'package:replay_protocol/replay_protocol.dart';

DiscoveredCamera? _parse({
  String serviceName = 'Pixel 7',
  List<String> addresses = const ['192.168.43.1'],
  int port = 8080,
  Map<String, String>? txt,
}) =>
    DiscoveredCamera.fromService(
      serviceName: serviceName,
      addresses: addresses,
      port: port,
      txt: txt ?? cameraTxt(cameraId: 'abc123', name: 'Google Pixel 7'),
    );

DiscoveredCamera _camera(String id, String name, {String host = '192.168.1.20'}) =>
    DiscoveredCamera(cameraId: id, name: name, host: host, port: 8080);

void main() {
  group('TXT record', () {
    test('carries the protocol version, install id and name (SPEC §4)', () {
      expect(cameraTxt(cameraId: 'abc123', name: 'Google Pixel 7'), {
        'v': '$protocolVersion',
        'cameraId': 'abc123',
        'name': 'Google Pixel 7',
      });
    });

    test('round-trips into a discovered camera', () {
      final camera = _parse()!;
      expect(camera.cameraId, 'abc123');
      expect(camera.name, 'Google Pixel 7');
      expect(camera.base, Uri.parse('http://192.168.43.1:8080'));
      expect(camera.compatible, isTrue);
    });

    test('falls back to the service name without a TXT name', () {
      expect(_parse(txt: {'v': '1', 'cameraId': 'abc123'})!.name, 'Pixel 7');
      expect(_parse(txt: {'v': '1', 'cameraId': 'abc123', 'name': '  '})!.name, 'Pixel 7');
    });

    test('ignores services that are not our Cameras', () {
      expect(_parse(txt: {'v': '1', 'name': 'x'}), isNull);
      expect(_parse(txt: {'cameraId': 'abc123'}), isNull);
      expect(_parse(txt: {'v': 'one', 'cameraId': 'abc123'}), isNull);
      expect(_parse(txt: const {}), isNull);
    });

    test('needs an IPv4 address and a valid port', () {
      expect(_parse(addresses: const []), isNull);
      expect(_parse(addresses: const ['fe80::1%wlan0']), isNull);
      expect(_parse(addresses: const ['999.1.1.1']), isNull);
      expect(_parse(addresses: const ['fe80::1', '10.0.0.5'])!.host, '10.0.0.5');
      expect(_parse(port: 0), isNull);
      expect(_parse(port: 70000), isNull);
    });

    test('another protocol version is listed but not compatible', () {
      final camera = _parse(txt: {'v': '${protocolVersion + 1}', 'cameraId': 'abc123', 'name': 'New'})!;
      expect(camera.compatible, isFalse);
    });
  });

  group('DiscoveredCameras', () {
    test('adds, updates and removes by service name', () {
      var cameras = const DiscoveredCameras();
      cameras = cameras.resolved('a', _camera('1', 'Bravo'));
      cameras = cameras.resolved('b', _camera('2', 'alpha'));
      expect(cameras.list.map((c) => c.name), ['alpha', 'Bravo']);

      cameras = cameras.resolved('a', _camera('1', 'Bravo', host: '10.0.0.9'));
      expect(cameras.list.last.host, '10.0.0.9');

      cameras = cameras.lost('b');
      expect(cameras.list.map((c) => c.name), ['Bravo']);
    });

    test('a Camera seen under two services shows once', () {
      final cameras = const DiscoveredCameras()
          .resolved('Pixel 7', _camera('1', 'Pixel 7'))
          .resolved('Pixel 7 (2)', _camera('1', 'Pixel 7', host: '10.0.0.9'));
      expect(cameras.list, hasLength(1));
      // It stays listed while either service is up.
      expect(cameras.lost('Pixel 7').list, hasLength(1));
    });

    test('losing an unknown service changes nothing', () {
      final cameras = const DiscoveredCameras().resolved('a', _camera('1', 'A'));
      expect(identical(cameras.lost('zzz'), cameras), isTrue);
    });
  });
}
