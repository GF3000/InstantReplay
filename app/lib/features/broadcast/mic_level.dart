import 'dart:async';

import 'package:flutter/foundation.dart';

/// The stream microphone's level on the Camera (SPEC §12.7), in dBFS; null without an open mic.
///
/// Polls [read] every [interval] (10 Hz) only while [active] and someone listens (the mic button
/// on screen, or the API server with viewers connected). Otherwise it does nothing and holds
/// null. [onRunning] hears when polling starts and stops (the Camera opens the microphone to
/// measure it before going live only meanwhile).
class MicLevelPoller extends ChangeNotifier implements ValueListenable<double?> {
  MicLevelPoller({required this.read, this.onRunning, this.interval = const Duration(milliseconds: 100)});

  final Future<double?> Function() read;
  final void Function(bool running)? onRunning;
  final Duration interval;

  Timer? _timer;
  bool _active = false;
  bool _busy = false;
  bool _disposed = false;
  double? _value;

  @override
  double? get value => _value;

  bool get active => _active;

  set active(bool on) {
    if (on == _active) return;
    _active = on;
    _sync();
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _sync();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final run = _active && hasListeners;
    if (run && _timer == null) {
      _timer = Timer.periodic(interval, (_) => _poll());
      onRunning?.call(true);
      _poll();
    } else if (!run) {
      if (_timer != null) onRunning?.call(false);
      _timer?.cancel();
      _timer = null;
      // Nobody left to tell (a widget may be unmounting): clear quietly.
      if (hasListeners) {
        _set(null);
      } else {
        _value = null;
      }
    }
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    double? db;
    try {
      db = await read();
    } catch (_) {
      db = null;
    }
    _busy = false;
    if (_timer != null) _set(db);
  }

  void _set(double? v) {
    if (_disposed || v == _value) return;
    _value = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_timer != null) onRunning?.call(false);
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
