import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:uuid/uuid.dart';

import '../data/viewer_api.dart';
import 'clip_store.dart';
import 'partial_download.dart';
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
/// Saves never wait for each other or for downloads; downloads run one at a time. A cut download
/// keeps what it received and resumes with a Range request, after a backoff or on reconnect.
class ClipTransfers {
  ClipTransfers({
    required this.store,
    required this.viewerId,
    required this.onChanged,
    this.presets = const SavePresets(),
    String Function()? newRequestId,
    PartialDownload Function(String clipId)? newPartial,
    this.retryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 8),
    this.stallTimeout = const Duration(seconds: 10),
    this.maxAttempts = 3,
  })  : _newRequestId = newRequestId ?? const Uuid().v4,
        _newPartial = newPartial ?? PartialDownload.platform;

  final ClipStore store;
  final String viewerId;
  /// Updated when Settings change; applies to the next save.
  SavePresets presets;
  final void Function(List<SessionClip> clips) onChanged;
  final String Function() _newRequestId;
  final PartialDownload Function(String clipId) _newPartial;

  /// First retry delay; it doubles on each failed attempt up to [maxRetryDelay].
  final Duration retryDelay;
  final Duration maxRetryDelay;

  /// A download that receives nothing for this long counts as cut (a Wi-Fi drop may not reset the
  /// connection).
  final Duration stallTimeout;

  /// Attempts per save and ack; for a download, consecutive attempts that receive nothing.
  final int maxAttempts;

  /// The Camera to talk to; null while not paired.
  ViewerApi? api;

  final _clips = <String, SessionClip>{};
  final _dtos = <String, ClipDto>{};
  final _queue = <ClipDto>[];

  /// What each unfinished download received so far, by clip id.
  final _partials = <String, PartialDownload>{};

  /// The clip id being downloaded.
  String? _active;
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
        if (attempt < maxAttempts) await _backoff(attempt);
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
        if (_active != dto.id) unawaited(_dropPartial(dto.id));
    }
    _put(c);
  }

  /// Tries a failed download again while the Camera still holds the clip.
  void retry(String requestId) {
    final c = _clips[requestId];
    final dto = _dtos[requestId];
    if (c == null || dto == null || c.phase != SessionClipPhase.failed) return;
    if (c.failure == ClipFailure.expired || dto.state != ClipState.ready) return;
    _put(c.copyWith(
      phase: SessionClipPhase.downloading,
      received: _partials[dto.id]?.length ?? 0,
      failure: () => null,
    ));
    _queue.add(dto);
    unawaited(_pump());
  }

  /// Picks up clips this viewer requested that are still in the outbox (after a reconnect), and
  /// resumes downloads that a network error cut.
  Future<void> recover() async {
    final api = this.api;
    if (api == null) return;
    try {
      for (final dto in await api.listClips()) {
        onClipChanged(dto);
        final c = _clips[dto.requestId];
        if (c != null && c.phase == SessionClipPhase.failed && c.failure == ClipFailure.download) retry(c.requestId);
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
    for (final id in _partials.keys.toList()) {
      if (id != _active) await _dropPartial(id);
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
    _active = dto.id;
    final partial = _partials[dto.id] ??= _newPartial(dto.id);
    var failure = ClipFailure.download;
    var stalled = 0; // Consecutive attempts that received nothing.
    var mismatches = 0;
    try {
      while (!_disposed) {
        final api = this.api;
        if (api == null) break;
        try {
          final size = dto.bytes;
          if (size == null || partial.length < size) {
            final before = partial.length;
            try {
              await _receive(api, dto, partial);
            } finally {
              if (partial.length > before) stalled = 0;
            }
            if (_disposed) break;
          }
          final bytes = await partial.read();
          final digest = sha256.convert(bytes).toString();
          final expected = dto.sha256?.toLowerCase();
          if (expected != null && expected != digest) {
            // Resuming cannot repair a bad byte: discard everything and download again from zero.
            await partial.clear();
            failure = ClipFailure.checksum;
            if (++mismatches >= maxAttempts) break;
            await _backoff(mismatches);
            continue;
          }
          final stored = await store.store(dto.id, bytes);
          await _dropPartial(dto.id);
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
        } on ApiException catch (e) {
          if (e.statusCode == 404) break; // Expired, or released by the Camera.
          if (e.statusCode == 416) await partial.clear(); // What we hold is not a prefix of the file.
          failure = ClipFailure.download;
          if (++stalled >= maxAttempts) break;
          await _backoff(stalled);
        } catch (_) {
          failure = ClipFailure.download;
          if (++stalled >= maxAttempts) break;
          await _backoff(stalled);
        }
      }
      // The partial stays for a manual retry or the next reconnect, unless the clip is gone.
      final c = _clips[dto.requestId];
      if (c != null && c.phase == SessionClipPhase.downloading) {
        _put(c.copyWith(phase: SessionClipPhase.failed, failure: () => failure));
      }
      if (_disposed || _clips[dto.requestId]?.failure == ClipFailure.expired) await _dropPartial(dto.id);
    } finally {
      _active = null;
    }
  }

  /// One request, from what [partial] holds to the end of the file or until the connection drops.
  Future<void> _receive(ViewerApi api, ClipDto dto, PartialDownload partial) async {
    final download = await api.openClipDownload(dto.id, offset: partial.length).timeout(stallTimeout);
    if (download.start == 0 && partial.length > 0) await partial.clear(); // The Camera ignored the range.
    final total = download.total ?? dto.bytes;
    var lastShown = -1.0;
    void progress() {
      final c = _clips[dto.requestId];
      if (c == null) return;
      final received = partial.length;
      final p = total == null || total == 0 ? 0.0 : received / total;
      if (p - lastShown < 0.02 && received != total) return; // Throttle UI updates.
      lastShown = p;
      _put(c.copyWith(received: received, total: () => total));
    }

    progress();
    await for (final chunk in download.body.timeout(stallTimeout)) {
      if (_disposed) return;
      await partial.append(chunk);
      progress();
    }
    if (total != null && partial.length < total) throw const _CutShort();
  }

  Future<void> _dropPartial(String clipId) async {
    try {
      await _partials.remove(clipId)?.delete();
    } catch (_) {
      // A temp file; the OS clears it eventually.
    }
  }

  Future<void> _backoff(int attempt) {
    final ms = retryDelay.inMilliseconds * (1 << (attempt - 1).clamp(0, 16));
    return Future<void>.delayed(Duration(milliseconds: ms.clamp(0, maxRetryDelay.inMilliseconds)));
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
        if (attempt < maxAttempts) await _backoff(attempt);
      } on UnauthorizedException {
        return;
      } catch (_) {
        if (attempt < maxAttempts) await _backoff(attempt);
      }
    }
  }
}

/// The connection closed before the whole file arrived.
class _CutShort implements Exception {
  const _CutShort();

  @override
  String toString() => 'Download cut short';
}
