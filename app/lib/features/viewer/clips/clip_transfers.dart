import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:uuid/uuid.dart';

import '../data/viewer_api.dart';
import 'clip_store.dart';
import 'save_presets.dart';

enum SessionClipPhase {
  /// POST /clips in flight.
  requesting,

  /// The Camera is cutting the clip (post-roll included).
  recording,

  /// Waiting for, or in, the download and checksum.
  downloading,

  /// Stored locally and playable.
  ready,
  failed,
}

enum ClipFailure { request, download, checksum, expired }

/// One clip saved from this Viewer in the current session.
@immutable
class SessionClip {
  const SessionClip({
    required this.requestId,
    required this.seconds,
    required this.requestedAt,
    required this.phase,
    this.clipId,
    this.durationMs,
    this.received = 0,
    this.total,
    this.stored,
    this.failure,
    this.acked = false,
  });

  final String requestId;

  /// Requested pre-roll.
  final double seconds;
  final DateTime requestedAt;
  final SessionClipPhase phase;
  final String? clipId;
  final int? durationMs;
  final int received;
  final int? total;
  final StoredClip? stored;
  final ClipFailure? failure;

  /// The Camera confirmed the checksum and released its copy.
  final bool acked;

  /// Download progress 0..1, or null when the size is unknown.
  double? get progress => total == null || total == 0 ? null : (received / total!).clamp(0, 1).toDouble();

  SessionClip copyWith({
    SessionClipPhase? phase,
    String? clipId,
    int? durationMs,
    int? received,
    int? Function()? total,
    StoredClip? stored,
    ClipFailure? Function()? failure,
    bool? acked,
  }) =>
      SessionClip(
        requestId: requestId,
        seconds: seconds,
        requestedAt: requestedAt,
        phase: phase ?? this.phase,
        clipId: clipId ?? this.clipId,
        durationMs: durationMs ?? this.durationMs,
        received: received ?? this.received,
        total: total == null ? this.total : total(),
        stored: stored ?? this.stored,
        failure: failure == null ? this.failure : failure(),
        acked: acked ?? this.acked,
      );
}

/// Save → ready → download → sha256 → ack (SPEC §5.2), for the clips this Viewer requested (D9).
///
/// Saves never wait for each other or for downloads; downloads run one at a time.
class ClipTransfers {
  ClipTransfers({
    required this.store,
    required this.viewerId,
    required this.onChanged,
    this.presets = const SavePresets(),
    String Function()? newRequestId,
    this.retryDelay = const Duration(seconds: 1),
    this.maxAttempts = 3,
  }) : _newRequestId = newRequestId ?? const Uuid().v4;

  final ClipStore store;
  final String viewerId;
  /// Updated when Settings change; applies to the next save.
  SavePresets presets;
  final void Function(List<SessionClip> clips) onChanged;
  final String Function() _newRequestId;
  final Duration retryDelay;
  final int maxAttempts;

  /// The Camera to talk to; null while not paired.
  ViewerApi? api;

  final _clips = <String, SessionClip>{};
  final _dtos = <String, ClipDto>{};
  final _queue = <ClipDto>[];
  bool _pumping = false;
  bool _disposed = false;

  /// Newest first.
  List<SessionClip> get clips => _clips.values.toList().reversed.toList(growable: false);

  /// Asks the Camera for a clip of [seconds] pre-roll (default preset when null). The caller may
  /// choose the [requestId] to refer to the clip before the Camera answers (e.g. to tag it).
  Future<void> save({int? seconds, String? requestId}) async {
    final api = this.api;
    if (api == null) return;
    final request = presets.request(requestId: requestId ?? _newRequestId(), viewerId: viewerId, seconds: seconds);
    _put(SessionClip(
      requestId: request.requestId,
      seconds: request.preSeconds,
      requestedAt: DateTime.now(),
      phase: SessionClipPhase.requesting,
    ));
    for (var attempt = 1; attempt <= maxAttempts && !_disposed; attempt++) {
      try {
        // A retry reuses the requestId, so the Camera never cuts the clip twice.
        onClipChanged(await api.saveClip(request));
        return;
      } on UnauthorizedException {
        break;
      } catch (_) {
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      }
    }
    final c = _clips[request.requestId];
    if (c != null && c.phase == SessionClipPhase.requesting) {
      _put(c.copyWith(phase: SessionClipPhase.failed, failure: () => ClipFailure.request));
    }
  }

  /// Handles a `clip_changed` event, a POST /clips response or an outbox listing entry.
  void onClipChanged(ClipDto dto) {
    if (_disposed) return;
    var c = _clips[dto.requestId];
    if (c == null) {
      // Requested by this viewer in an earlier page load or before a reconnect: adopt it.
      if (dto.requestedBy != viewerId) return;
      if (dto.state != ClipState.recording && dto.state != ClipState.ready) return;
      c = SessionClip(
        requestId: dto.requestId,
        seconds: (dto.durationMs ?? 0) / 1000,
        requestedAt: DateTime.fromMillisecondsSinceEpoch(dto.createdAtMs),
        phase: SessionClipPhase.recording,
      );
    }
    _dtos[dto.requestId] = dto;
    c = c.copyWith(clipId: dto.id, durationMs: dto.durationMs);
    switch (dto.state) {
      case ClipState.recording:
        if (c.phase == SessionClipPhase.requesting) c = c.copyWith(phase: SessionClipPhase.recording);
      case ClipState.ready:
        if (c.phase == SessionClipPhase.requesting || c.phase == SessionClipPhase.recording) {
          c = c.copyWith(phase: SessionClipPhase.downloading, received: 0, total: () => dto.bytes);
          _queue.add(dto);
          unawaited(_pump());
        }
      case ClipState.acked:
        break;
      case ClipState.expired:
        if (c.phase != SessionClipPhase.ready) {
          _queue.removeWhere((q) => q.requestId == dto.requestId);
          c = c.copyWith(phase: SessionClipPhase.failed, failure: () => ClipFailure.expired);
        }
    }
    _put(c);
  }

  /// Tries a failed download again while the Camera still holds the clip.
  void retry(String requestId) {
    final c = _clips[requestId];
    final dto = _dtos[requestId];
    if (c == null || dto == null || c.phase != SessionClipPhase.failed) return;
    if (c.failure == ClipFailure.expired || dto.state != ClipState.ready) return;
    _put(c.copyWith(phase: SessionClipPhase.downloading, received: 0, failure: () => null));
    _queue.add(dto);
    unawaited(_pump());
  }

  /// Picks up clips this viewer requested that are still in the outbox (after a reconnect).
  Future<void> recover() async {
    final api = this.api;
    if (api == null) return;
    try {
      for (final dto in await api.listClips()) {
        onClipChanged(dto);
      }
    } catch (_) {
      // Best effort: live events still arrive.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    for (final c in _clips.values) {
      await c.stored?.release();
    }
  }

  void _put(SessionClip c) {
    if (_disposed) return;
    _clips[c.requestId] = c;
    onChanged(clips);
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        await _transfer(_queue.removeAt(0));
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _transfer(ClipDto dto) async {
    var failure = ClipFailure.download;
    for (var attempt = 1; attempt <= maxAttempts && !_disposed; attempt++) {
      final api = this.api;
      if (api == null) break;
      try {
        var lastShown = -1.0;
        final bytes = await api.downloadClip(dto.id, onProgress: (received, total) {
          final c = _clips[dto.requestId];
          if (c == null) return;
          final t = total ?? dto.bytes;
          final p = t == null || t == 0 ? 0.0 : received / t;
          if (p - lastShown < 0.02 && received != t) return; // Throttle UI updates.
          lastShown = p;
          _put(c.copyWith(received: received, total: () => t));
        });
        final digest = sha256.convert(bytes).toString();
        final expected = dto.sha256?.toLowerCase();
        if (expected != null && expected != digest) {
          failure = ClipFailure.checksum;
          if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
          continue;
        }
        final stored = await store.store(dto.id, bytes);
        final c = _clips[dto.requestId];
        if (c == null || _disposed) {
          await stored.release();
          return;
        }
        _put(c.copyWith(
          phase: SessionClipPhase.ready,
          stored: stored,
          received: bytes.length,
          total: () => bytes.length,
          failure: () => null,
        ));
        await _ack(api, dto, digest);
        return;
      } on UnauthorizedException {
        break;
      } catch (_) {
        failure = ClipFailure.download;
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      }
    }
    final c = _clips[dto.requestId];
    if (c != null && c.phase == SessionClipPhase.downloading) {
      _put(c.copyWith(phase: SessionClipPhase.failed, failure: () => failure));
    }
  }

  Future<void> _ack(ViewerApi api, ClipDto dto, String digest) async {
    for (var attempt = 1; attempt <= maxAttempts && !_disposed; attempt++) {
      try {
        await api.ack(dto.id, digest);
        final c = _clips[dto.requestId];
        if (c != null) _put(c.copyWith(acked: true));
        return;
      } on ApiException catch (e) {
        if (e.statusCode == 409) return; // The Camera disagrees on the hash; it keeps its copy until expiry.
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      } on UnauthorizedException {
        return;
      } catch (_) {
        if (attempt < maxAttempts) await Future<void>.delayed(retryDelay);
      }
    }
  }
}
