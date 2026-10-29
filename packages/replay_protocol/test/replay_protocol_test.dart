import 'package:replay_protocol/replay_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('exposes protocol constants', () {
    expect(protocolVersion, 1);
    expect(serviceType, '_instantreplay._tcp');
  });
}
