import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:replay_protocol/replay_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../core/preferences.dart';
import 'clips/clip_store.dart';
import 'clips/clip_transfers.dart';
import 'clips/save_presets.dart';
import 'data/page_url.dart';
import 'data/session_link.dart';
import 'data/viewer_api.dart';
import 'live/live_signaling.dart';
import 'live/webrtc_live_peer.dart';

// region Injection points (overridden in tests)

final viewerHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final channelConnectorProvider = Provider<ChannelConnector>((_) => connectWebSocket);

final livePeerFactoryProvider = Provider<LivePeerFactory>((_) => createWebRtcLivePeer);

final clipStoreProvider = Provider<ClipStore>((_) => ClipStore.platform());

final savePresetsProvider = Provider<SavePresets>((_) => const SavePresets());

/// The page address on web (the Camera serves the bundle, so its origin is the Camera); null on Android.
final pageUriProvider = Provider<Uri?>((_) => kIsWeb ? Uri.base : null);

// endregion

/// Stable id of this Viewer install (D9): the Camera sends a clip only to the viewer that asked.
final viewerIdProvider = Provider<String>((ref) {
  const key = 'viewer.id';
  final prefs = ref.watch(sharedPreferencesProvider);
  final saved = prefs.getString(key);
  if (saved != null) return saved;
  final id = const Uuid().v4();
  unawaited(prefs.setString(key, id));
  return id;
});

// region Connection setup

enum PairError { invalidAddress, wrongCode, tooManyAttempts, unreachable, sessionExpired }

@immutable
class ViewerSetup {
  const ViewerSetup({this.base, this.token, this.addressFixed = false, this.busy = false, this.error});

  /// `http://host:port` of the Camera; null until known.
  final Uri? base;
  final String? token;

  /// Web: the address is the page origin and cannot be changed.
  final bool addressFixed;
  final bool busy;
  final PairError? error;

  bool get paired => base != null && token != null;

  ViewerSetup copyWith({Uri? Function()? base, String? Function()? token, bool? busy, PairError? Function()? error}) =>
      ViewerSetup(
        base: base == null ? this.base : base(),
        token: token == null ? this.token : token(),
        addressFixed: addressFixed,
        busy: busy ?? this.busy,
        error: error == null ? this.error : error(),
      );
}

/// Which Camera to talk to and its token. Tokens are kept per Camera (D19).
class ViewerSetupNotifier extends Notifier<ViewerSetup> {
  static const _lastCameraKey = 'viewer.lastCamera';
  static String _tokenKey(Uri base) => 'viewer.token.${cameraKey(base)}';

  @override
  ViewerSetup build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final page = ref.watch(pageUriProvider);
    if (page != null) {
      // Normally the Camera serves the page, so its origin is the Camera.
      final link = parseCameraLink(page);
      if (link == null) return const ViewerSetup(addressFixed: true);
      final base = link.base;
      // The Camera's QR opens `http://ip:port/?k=<token>`: take the token and hide it.
      if (link.token case final fromQr?) {
        unawaited(prefs.setString(_tokenKey(base), fromQr));
        stripTokenFromPageUrl();
        return ViewerSetup(base: base, token: fromQr, addressFixed: true);
      }
      return ViewerSetup(base: base, token: prefs.getString(_tokenKey(base)), addressFixed: true);
    }
    final saved = prefs.getString(_lastCameraKey);
    final base = saved == null ? null : normalizeCameraAddress(saved);
    return ViewerSetup(base: base, token: base == null ? null : prefs.getString(_tokenKey(base)));
  }

  /// Android (no NSD yet): the typed Camera address.
  Future<bool> setAddress(String raw) async {
    final base = normalizeCameraAddress(raw);
    if (base == null) {
      state = state.copyWith(error: () => PairError.invalidAddress);
      return false;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_lastCameraKey, cameraKey(base));
    state = state.copyWith(base: () => base, token: () => prefs.getString(_tokenKey(base)), error: () => null);
    return true;
  }

  /// Android: the Camera's QR, read by the in-app scanner. With its token the Viewer is paired
  /// at once; without one it goes on to the code. A stale token is caught by the session link,
  /// which falls back to the code (see [forgetToken]).
  Future<void> connectTo(CameraLink link) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_lastCameraKey, cameraKey(link.base));
    if (link.token case final token?) await prefs.setString(_tokenKey(link.base), token);
    if (!ref.mounted) return;
    state = state.copyWith(
      base: () => link.base,
      token: () => link.token ?? prefs.getString(_tokenKey(link.base)),
      error: () => null,
    );
  }

  /// Exchanges the 6-digit code for the token (POST /pair).
  Future<bool> pair(String code) async {
    final base = state.base;
    if (base == null || state.busy) return false;
    state = state.copyWith(busy: true, error: () => null);
    PairError? error;
    try {
      final token = await ViewerApi(client: ref.read(viewerHttpClientProvider), base: base).pair(code.trim());
      if (!ref.mounted) return false;
      await ref.read(sharedPreferencesProvider).setString(_tokenKey(base), token);
      if (!ref.mounted) return false;
      state = state.copyWith(token: () => token, busy: false);
      return true;
    } on UnauthorizedException {
      error = PairError.wrongCode;
    } on ApiException catch (e) {
      error = e.statusCode == 429 ? PairError.tooManyAttempts : PairError.wrongCode;
    } catch (_) {
      error = PairError.unreachable;
    }
    if (ref.mounted) state = state.copyWith(busy: false, error: () => error);
    return false;
  }

  /// The Camera rejected the token (it restarted or regenerated it): ask for a new code.
  Future<void> forgetToken({bool expired = false}) async {
    final base = state.base;
    if (base != null) await ref.read(sharedPreferencesProvider).remove(_tokenKey(base));
    if (!ref.mounted) return;
    state = state.copyWith(token: () => null, error: () => expired ? PairError.sessionExpired : null);
  }

  /// Android: go back to the address field.
  Future<void> changeCamera() async {
    if (state.addressFixed) return;
    await ref.read(sharedPreferencesProvider).remove(_lastCameraKey);
    if (!ref.mounted) return;
    state = state.copyWith(base: () => null, token: () => null, error: () => null);
  }
}

final viewerSetupProvider = NotifierProvider.autoDispose<ViewerSetupNotifier, ViewerSetup>(ViewerSetupNotifier.new);

/// REST client for the paired Camera; null until paired.
final viewerApiProvider = Provider.autoDispose<ViewerApi?>((ref) {
  final (base, token) = ref.watch(viewerSetupProvider.select((s) => (s.base, s.token)));
  if (base == null || token == null) return null;
  return ViewerApi(client: ref.watch(viewerHttpClientProvider), base: base, token: token);
});

// endregion

// region Session

/// The WebSocket session with the paired Camera; null until paired.
final sessionLinkProvider = Provider.autoDispose<SessionLink?>((ref) {
  final api = ref.watch(viewerApiProvider);
  if (api == null) return null;
  final link = SessionLink(api: api, viewerId: ref.watch(viewerIdProvider), connect: ref.watch(channelConnectorProvider));
  ref.onDispose(link.dispose);
  link.start();
  return link;
});

class LinkStateNotifier extends Notifier<LinkState?> {
  @override
  LinkState? build() {
    final link = ref.watch(sessionLinkProvider);
    if (link == null) return null;
    final sub = link.states.listen((s) {
      state = s;
      if (s.phase == LinkPhase.unauthorized) unawaited(ref.read(viewerSetupProvider.notifier).forgetToken(expired: true));
    });
    ref.onDispose(sub.cancel);
    return link.state;
  }
}

final linkStateProvider = NotifierProvider.autoDispose<LinkStateNotifier, LinkState?>(LinkStateNotifier.new);

// endregion

// region Live view

enum LivePhase {
  /// Not connected to the Camera.
  waiting,

  /// LiveStart sent; offer/answer/ICE in progress.
  negotiating,
  playing,

  /// Lost; a restart is scheduled.
  interrupted,
}

@immutable
class LiveViewState {
  const LiveViewState({required this.phase, this.peer});

  final LivePhase phase;
  final LivePeer? peer;
}

/// Receive-only live view (SPEC §4.2): LiveStart → RtcOffer → RtcAnswer, trickle ICE both ways,
/// and a restart whenever the call fails or stalls.
class LiveViewNotifier extends Notifier<LiveViewState> {
  static const negotiationTimeout = Duration(seconds: 12);
  static const disconnectGrace = Duration(seconds: 4);
  static const restartDelay = Duration(seconds: 2);

  SessionLink? _link;
  late LiveSignaling _signaling;
  LivePeer? _peer;
  Timer? _timer;
  int _generation = 0;
  LinkPhase? _linkPhase;

  @override
  LiveViewState build() {
    final link = ref.watch(sessionLinkProvider);
    _link = link;
    _signaling = LiveSignaling(send: (m) => _link?.send(m));
    _linkPhase = null;
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      _signaling.detach();
      final peer = _peer;
      _peer = null;
      unawaited(peer?.dispose());
    });
    if (link == null) return const LiveViewState(phase: LivePhase.waiting);
    final msgSub = link.messages.listen(_onMessage);
    final stateSub = link.states.listen((s) => _onLinkPhase(s.phase));
    ref.onDispose(msgSub.cancel);
    ref.onDispose(stateSub.cancel);
    if (link.isConnected) scheduleMicrotask(() => _onLinkPhase(LinkPhase.connected));
    return const LiveViewState(phase: LivePhase.waiting);
  }

  /// Tears down the call and negotiates a new one.
  void restart() {
    if (_link?.isConnected ?? false) unawaited(_start());
  }

  void _onLinkPhase(LinkPhase phase) {
    if (!ref.mounted || phase == _linkPhase) return;
    _linkPhase = phase;
    if (phase == LinkPhase.connected) {
      unawaited(_start());
    } else {
      _generation++;
      _timer?.cancel();
      unawaited(_stopPeer());
      state = const LiveViewState(phase: LivePhase.waiting);
    }
  }

  Future<void> _start() async {
    final gen = ++_generation;
    _timer?.cancel();
    final hadPeer = _peer != null;
    await _stopPeer();
    if (hadPeer) _link?.send(const LiveStop());
    if (!ref.mounted || gen != _generation) return;
    state = const LiveViewState(phase: LivePhase.negotiating);
    final LivePeer peer;
    try {
      peer = await ref.read(livePeerFactoryProvider)(
        onLocalCandidate: (c) {
          if (gen == _generation) _signaling.onLocalCandidate(c);
        },
        onState: (s) {
          if (gen == _generation) _onPeerState(s);
        },
      );
    } catch (_) {
      _scheduleRestart(gen);
      return;
    }
    if (!ref.mounted || gen != _generation) {
      await peer.dispose();
      return;
    }
    _peer = peer;
    _signaling.attach(peer);
    state = LiveViewState(phase: LivePhase.negotiating, peer: peer);
    _link?.send(const LiveStart());
    _timer = Timer(negotiationTimeout, () => _scheduleRestart(gen));
  }

  Future<void> _stopPeer() async {
    _signaling.detach();
    final peer = _peer;
    _peer = null;
    await peer?.dispose();
  }

  void _onMessage(WsMessage msg) {
    if (!ref.mounted) return;
    final gen = _generation;
    Future<void> guarded(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {
        _scheduleRestart(gen);
      }
    }

    switch (msg) {
      case RtcOffer(:final sdp):
        if (_peer != null) unawaited(guarded(() => _signaling.onOffer(sdp)));
      case RtcIce():
        unawaited(guarded(() => _signaling.onRemoteCandidate(msg)));
      // A Welcome on a live link means the Camera restarted capture (e.g. new resolution) and
      // dropped every call: negotiate again now instead of waiting for ours to time out.
      case Welcome() when _linkPhase == LinkPhase.connected && _peer != null:
        restart();
      case ErrorMessage(code: 'live_failed'):
        _scheduleRestart(gen);
      default:
    }
  }

  void _onPeerState(LivePeerState s) {
    if (!ref.mounted) return;
    final gen = _generation;
    switch (s) {
      case LivePeerState.connected:
        _timer?.cancel();
        state = LiveViewState(phase: LivePhase.playing, peer: _peer);
      case LivePeerState.connecting:
        break;
      case LivePeerState.disconnected:
        // Often recovers by itself; restart only if it does not.
        state = LiveViewState(phase: LivePhase.interrupted, peer: _peer);
        _timer?.cancel();
        _timer = Timer(disconnectGrace, () => _scheduleRestart(gen));
      case LivePeerState.failed:
      case LivePeerState.closed:
        _scheduleRestart(gen);
    }
  }

  void _scheduleRestart(int gen) {
    if (!ref.mounted || gen != _generation) return;
    _timer?.cancel();
    state = LiveViewState(phase: LivePhase.interrupted, peer: _peer);
    _timer = Timer(restartDelay, () {
      if (ref.mounted && gen == _generation) restart();
    });
  }
}

final liveViewProvider = NotifierProvider.autoDispose<LiveViewNotifier, LiveViewState>(LiveViewNotifier.new);

// endregion

// region Clips

/// Clips saved in this session, newest first. Survives reconnects; lost when the page closes (D15).
class ViewerClipsNotifier extends Notifier<List<SessionClip>> {
  ClipTransfers? _transfers;

  @override
  List<SessionClip> build() {
    final transfers = ClipTransfers(
      store: ref.watch(clipStoreProvider),
      viewerId: ref.watch(viewerIdProvider),
      presets: ref.watch(savePresetsProvider),
      onChanged: (clips) {
        if (ref.mounted) state = clips;
      },
    );
    _transfers = transfers;
    ref.onDispose(transfers.dispose);
    ref.listen(viewerApiProvider, (_, api) => transfers.api = api, fireImmediately: true);
    StreamSubscription<WsMessage>? sub;
    ref.listen(sessionLinkProvider, (_, link) {
      unawaited(sub?.cancel());
      sub = link?.messages.listen((m) {
        switch (m) {
          case ClipChanged(:final clip):
            transfers.onClipChanged(clip);
          case Welcome():
            unawaited(transfers.recover());
          default:
        }
      });
    }, fireImmediately: true);
    ref.onDispose(() => sub?.cancel());
    return const [];
  }

  /// Never waits for earlier saves or downloads. Returns the requestId of the new clip, or null when
  /// not paired.
  String? save({int? seconds}) {
    final transfers = _transfers;
    if (transfers?.api == null) return null;
    final requestId = const Uuid().v4();
    unawaited(transfers!.save(seconds: seconds, requestId: requestId));
    return requestId;
  }

  void retry(String requestId) => _transfers?.retry(requestId);
}

final viewerClipsProvider = NotifierProvider.autoDispose<ViewerClipsNotifier, List<SessionClip>>(ViewerClipsNotifier.new);

/// Thumbnail of a stored clip, grabbed once per clip (web); null where unsupported.
/// Kept while a tile shows it and a few minutes after, so scrolling back doesn't decode the clip
/// again, but released clips don't pin their thumbnails for the whole session.
final clipThumbnailProvider = FutureProvider.autoDispose.family<Uint8List?, StoredClip>((ref, clip) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() => release = Timer(const Duration(minutes: 5), link.close));
  ref.onResume(() => release?.cancel());
  ref.onDispose(() => release?.cancel());
  return clip.thumbnail();
});

// endregion
