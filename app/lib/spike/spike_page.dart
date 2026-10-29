import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

import 'spike_server.dart';

/// Phase 0 harness: runs the capture pipeline, saves clips, serves them on the LAN and
/// logs a soak-test CSV (every 10 s) next to the clips.
class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  static const _thermalNames = ['none', 'light', 'moderate', 'severe', 'critical', 'emergency', 'shutdown'];

  CaptureProfile _profile = CaptureProfile.standard;
  CaptureSession? _session;
  SpikeServer? _server;
  String? _serverUrl;
  Map<Object?, Object?> _stats = const {};
  final List<String> _log = [];
  StreamSubscription<Map<Object?, Object?>>? _events;
  IOSink? _soakCsv;
  DateTime? _startedAt;
  int _statsCount = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _events = ReplayCapture.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _stop();
    super.dispose();
  }

  void _onEvent(Map<Object?, Object?> e) {
    switch (e['type']) {
      case 'stats':
        setState(() => _stats = e);
        if (++_statsCount % 10 == 0) _writeSoakRow(e);
      case 'error':
        _addLog('ERROR ${e['message']}');
      default:
        _addLog('$e');
    }
  }

  void _addLog(String line) => setState(() {
        _log.insert(0, '${TimeOfDay.now().format(context)}  $line');
        if (_log.length > 50) _log.removeLast();
      });

  Future<void> _start() async {
    if (!await ReplayCapture.requestPermission()) {
      _addLog('Camera permission denied');
      return;
    }
    try {
      final session = await ReplayCapture.start(_profile);
      final server = SpikeServer(clipsDir: session.clipsDir, stats: () => _stats, save: _save);
      final port = await server.start();
      final ip = await _localIp();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      _soakCsv = File('${session.clipsDir}/soak_${_profile.label}_$stamp.csv').openWrite()
        ..writeln('elapsed_s,fps,encoded_frames,gaps,thermal_status,thermal_headroom,buffer_ms,buffer_bytes,'
            'battery_temp_c,battery_pct,plugged,battery_current_ma');
      setState(() {
        _session = session;
        _server = server;
        _serverUrl = 'http://$ip:$port';
        _startedAt = DateTime.now();
        _statsCount = 0;
      });
      _addLog('Started ${_profile.label} · ${session.encoder} · High=${session.highProfile} · '
          'sensor ${session.sensorOrientation}°');
    } catch (e) {
      _addLog('Start failed: $e');
    }
  }

  Future<void> _stop() async {
    await _server?.stop();
    await _soakCsv?.close();
    _soakCsv = null;
    if (_session != null) await ReplayCapture.stop();
    if (!mounted) return;
    setState(() {
      _session = null;
      _server = null;
      _serverUrl = null;
    });
  }

  Future<SavedClip> _save(double pre, double post) async {
    setState(() => _saving = true);
    final watch = Stopwatch()..start();
    try {
      final clip = await ReplayCapture.saveClip(preSeconds: pre, postSeconds: post);
      _addLog('Saved ${clip.name}: ${(clip.durationMs / 1000).toStringAsFixed(1)} s, '
          '${(clip.bytes / 1e6).toStringAsFixed(1)} MB, assembly ${clip.assemblyMs} ms, '
          'total ${watch.elapsedMilliseconds} ms');
      return clip;
    } catch (e) {
      _addLog('Save failed: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _writeSoakRow(Map<Object?, Object?> s) {
    final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
    _soakCsv?.writeln([
      elapsed,
      (s['fps'] as num).toStringAsFixed(1),
      s['encodedFrames'],
      s['gaps'],
      s['thermalStatus'],
      s['thermalHeadroom'] ?? '',
      s['bufferMs'],
      s['bufferBytes'],
      s['batteryTempC'] ?? '',
      s['batteryPercent'] ?? '',
      s['plugged'] ?? '',
      s['batteryCurrentMa'] ?? '',
    ].join(','));
  }

  Future<String> _localIp() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) return a.address;
      }
    }
    return '0.0.0.0';
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: session == null
                      ? const ColoredBox(color: Color(0xFF1A1A1A))
                      : Texture(textureId: session.textureId),
                ),
              ),
            ),
            SizedBox(width: 340, child: _panel(session)),
          ],
        ),
      ),
    );
  }

  Widget _panel(CaptureSession? session) {
    final s = _stats;
    final mb = ((s['bufferBytes'] as int?) ?? 0) / 1e6;
    final thermal = (s['thermalStatus'] as int?) ?? 0;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          DropdownButton<CaptureProfile>(
            value: _profile,
            items: [for (final p in CaptureProfile.all) DropdownMenuItem(value: p, child: Text(p.label))],
            onChanged: session == null ? (p) => setState(() => _profile = p!) : null,
          ),
          const Spacer(),
          FilledButton(onPressed: session == null ? _start : _stop, child: Text(session == null ? 'Start' : 'Stop')),
        ]),
        if (_serverUrl != null) SelectableText('Server: $_serverUrl', style: const TextStyle(color: Colors.amber)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final pre in [10, 20, 30, 60])
            FilledButton.tonal(
              onPressed: session == null || _saving ? null : () => _save(pre.toDouble(), 2),
              child: Text('Save $pre s'),
            ),
        ]),
        const Divider(),
        _stat('fps', (s['fps'] as num?)?.toStringAsFixed(1)),
        _stat('encoded frames', s['encodedFrames']),
        _stat('gaps', s['gaps']),
        _stat('dropped before key', s['droppedBeforeKeyframe']),
        _stat('buffer', '${((s['bufferMs'] as int?) ?? 0) ~/ 1000} s · ${mb.toStringAsFixed(0)} MB · '
            '${s['fragments'] ?? 0} frags'),
        _stat('thermal', '${_thermalNames[thermal.clamp(0, 6)]} · headroom ${s['thermalHeadroom'] ?? '–'}'),
        _stat('battery', '${s['batteryTempC'] ?? '–'} °C · ${s['batteryPercent'] ?? '–'} % · '
            '${s['plugged'] == true ? 'plugged' : 'unplugged'} · ${s['batteryCurrentMa'] ?? '–'} mA'),
        const Divider(),
        for (final line in _log) Text(line, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  Widget _stat(String label, Object? value) => Row(children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white54))),
        Expanded(child: Text('${value ?? '–'}', style: const TextStyle(color: Colors.white))),
      ]);
}
