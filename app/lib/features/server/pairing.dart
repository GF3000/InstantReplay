import 'dart:math';

/// The secrets of one Camera run (SPEC §4): a 6-digit code to type on a Viewer and the 128-bit
/// token it is exchanged for. A new run means new secrets, so old viewers must pair again.
class PairingSecrets {
  PairingSecrets({required this.code, required this.token});

  factory PairingSecrets.generate([Random? random]) {
    final r = random ?? Random.secure();
    final code = List.generate(6, (_) => r.nextInt(10)).join();
    final token = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return PairingSecrets(code: code, token: token);
  }

  final String code;

  /// 32 lowercase hex characters, safe in URLs.
  final String token;

  bool matchesCode(String candidate) => constantTimeEquals(candidate.trim(), code);

  bool matchesToken(String? candidate) => candidate != null && constantTimeEquals(candidate, token);
}

/// Compares without an early exit, so response timing does not leak how much of a secret matched.
bool constantTimeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// Sliding-window limit of attempts per key (the remote address for `/pair`).
class AttemptLimiter {
  AttemptLimiter({this.maxAttempts = 5, this.window = const Duration(minutes: 1), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _now;
  final _attempts = <String, List<DateTime>>{};

  /// Records an attempt for [key]; false when the key already used up its window.
  bool tryAcquire(String key) {
    final now = _now();
    final recent = (_attempts[key] ?? const <DateTime>[]).where((t) => now.difference(t) < window).toList();
    if (recent.length >= maxAttempts) {
      _attempts[key] = recent;
      return false;
    }
    _attempts[key] = recent..add(now);
    return true;
  }
}
