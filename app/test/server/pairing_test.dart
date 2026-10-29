import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/server/pairing.dart';
import 'package:instant_replay/features/server/server_platform_io.dart';

void main() {
  test('generated secrets: 6-digit code and 128-bit hex token, different per run', () {
    final a = PairingSecrets.generate();
    final b = PairingSecrets.generate(Random(1));
    expect(a.code, matches(RegExp(r'^\d{6}$')));
    expect(a.token, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a.token, isNot(b.token));
    expect(a.matchesCode(' ${a.code} '), isTrue);
    expect(a.matchesToken(null), isFalse);
    expect(a.matchesToken(a.token.substring(1)), isFalse);
  });

  test('the limiter allows 5 attempts per key per minute', () {
    var now = DateTime(2026);
    final limiter = AttemptLimiter(now: () => now);
    for (var i = 0; i < 5; i++) {
      expect(limiter.tryAcquire('a'), isTrue);
    }
    expect(limiter.tryAcquire('a'), isFalse);
    expect(limiter.tryAcquire('b'), isTrue);
    now = now.add(const Duration(seconds: 61));
    expect(limiter.tryAcquire('a'), isTrue);
  });

  test('picks the Wi-Fi or hotspot address', () {
    expect(pickLocalAddress([]), isNull);
    expect(
      pickLocalAddress([
        (name: 'rmnet_data0', address: '10.12.0.5'),
        (name: 'wlan0', address: '192.168.1.20'),
      ]),
      '192.168.1.20',
    );
    expect(
      pickLocalAddress([
        (name: 'rmnet_data0', address: '10.12.0.5'),
        (name: 'swlan0', address: '10.0.0.1'),
      ]),
      '10.0.0.1',
    );
    expect(
      pickLocalAddress([
        (name: 'eth9', address: '8.8.8.8'),
        (name: 'eth1', address: '172.20.1.2'),
      ]),
      '172.20.1.2',
    );
  });
}
