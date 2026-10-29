import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:replay_capture_android/replay_capture_android.dart';

import 'spike_server.dart';

/// Phase 0 harness: runs the capture pipeline, saves clips and serves them on the LAN.
/// Soak tests poll `/api/stats` from a PC (see docs/dev-setup.md).
class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  static const _thermalNames = ['none', 'light', 'moderate', 'severe', 'critical', 'emergency', 'shutdown'];

  final _capture = ReplayCapture.instance;
  List<CaptureProfile> _profiles = const [];
  String? _profileId;
  StartResult? _session;
  SpikeServer? _server;
  String? _serverUrl;
  CaptureStats? _stats;
  final List<String> _log = [];
  final List<StreamSubscription<Object>> _subs = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_capture.stats.listen((s) => setState(() => _stats = s)))
      ..add(_capture.errors.listen((m) => _addLog('ERROR $m')))
      ..add(_capture.cameraState.listen((s) => _addLog('camera: $s')))
      ..add(_capture.thermal.listen((t) => _addLog('thermal: ${t.status} → ${t.action.name}')));
    _capture.supportedProfiles().then((p) => setState(() {
          _profiles = p;
          _profileId = p.any((x) => x.id == '1080p30') ? '1080p30' : p.firstOrNull?.id;
        }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _stop();
    super.dispose();
  }

  void _addLog(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $line');
      if (_log.length > 50) _log.removeLast();
    });
  }

  Future<void> _start() async {
    final profileId = _profileId;
    if (profileId == null) return;
    if (!await _capture.requestPermission()) {
      _addLog('Camera permission denied');
      return;
    }
    try {
      final session = await _capture.start(profileId);
      final server = SpikeServer(stats: () => _stats, save: _save);
      final port = await server.start();
      final ip = await _localIp();
      setState(() {
        _session = session;
        _server = server;
        _serverUrl = 'http://$ip:$port';
      });
      _addLog('Started $profileId · ${session.encoder} · High=${session.highProfile} · '
          'sensor ${session.sensorOrientation}°');
    } catch (e) {
      _addLog('Start failed: $e');
    }
  }

  Future<void> _stop() async {
    await _server?.stop();
    if (_session != null) await _capture.stop();
    if (!mounted) return;
    setState(() {
      _session = null;
      _server = null;
      _serverUrl = null;
    });
  }

  Future<ClipInfo> _save(double pre, double post) async {
    setState(() => _saving = true);
    final watch = Stopwatch()..start();
    try {
      final clip = await _capture.saveClip(
        requestId: 'lab-${DateTime.now().microsecondsSinceEpoch}',
        preSeconds: pre,
        postSeconds: post,
      );
      _addLog('Saved ${clip.id.substring(0, 8)}: ${((clip.durationMs ?? 0) / 1000).toStringAsFixed(1)} s, '
          '${((clip.bytes ?? 0) / 1e6).toStringAsFixed(1)} MB, assembly ${clip.assemblyMs} ms, '
          'total ${watch.elapsedMilliseconds} ms');
      return clip;
    } catch (e) {
      _addLog('Save failed: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  Widget _panel(StartResult? session) {
    final s = _stats;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          DropdownButton<String>(
            value: _profileId,
            items: [for (final p in _profiles) DropdownMenuItem(value: p.id, child: Text(p.id))],
            onChanged: session == null ? (id) => setState(() => _profileId = id) : null,
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
        if (s != null) ...[
          _stat('fps', s.fps.toStringAsFixed(1)),
          _stat('encoded frames', s.encodedFrames),
          _stat('gaps', '${s.gaps} (camera ${s.cameraGaps}, GL ${s.glGaps})'),
          _stat('buffer', '${s.bufferMs ~/ 1000} s · ${(s.bufferBytes / 1e6).toStringAsFixed(0)} MB'),
          _stat('outbox', '${s.outboxClips} clips · ${(s.outboxBytes / 1e6).toStringAsFixed(0)} MB'),
          _stat('thermal', '${_thermalNames[s.thermalStatus.clamp(0, 6)]} · headroom ${s.thermalHeadroom ?? '–'}'),
          _stat('battery', '${s.batteryTempC ?? '–'} °C · ${s.batteryPercent ?? '–'} % · '
              '${s.plugged ? 'plugged' : 'unplugged'}'),
        ],
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
