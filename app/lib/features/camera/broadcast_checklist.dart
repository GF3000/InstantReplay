import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show CaptureProfile;

import '../../core/ui/ir_colors.dart';
import '../../l10n/app_localizations.dart';
import '../broadcast/broadcast_providers.dart';
import '../broadcast/broadcast_widgets.dart';
import '../broadcast/preflight.dart';
import 'camera_session.dart';
import 'capture_layer.dart';
import '../broadcast/youtube/youtube_providers.dart';

/// What to check before going live (SPEC §12.7): stream key, 1080p, Internet, charging and the
/// microphone, each with the fix at hand: a green check, or an amber warning with its button.
/// Hidden on air. On the Camera's screen it shows only what is missing, and nothing once
/// everything is fine (no "all good" line taking room); inside "Prepare the stream" ([inPage])
/// every line stays.
class BroadcastChecklist extends ConsumerStatefulWidget {
  const BroadcastChecklist({super.key, this.inPage = false});

  /// Inside the stream settings page: no title, no "add the key" button (the page is where it
  /// goes), and the green lines stay.
  final bool inPage;

  /// How often Internet and the microphone permission are checked again.
  static const recheckEvery = Duration(seconds: 15);

  @override
  ConsumerState<BroadcastChecklist> createState() => _BroadcastChecklistState();
}

class _BroadcastChecklistState extends ConsumerState<BroadcastChecklist> {
  bool? _internet;
  bool? _mic;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_recheck());
    _timer = Timer.periodic(BroadcastChecklist.recheckEvery, (_) => _recheck());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _recheck() async {
    // The list may be gone (on air, page closed) by the time a dialog or permission prompt returns.
    if (!mounted) return;
    final server = ref.read(broadcastControllerProvider).info.server;
    final capture = ref.read(captureLayerProvider);
    final results = await Future.wait([
      ref.read(streamServerReachableProvider)(server),
      capture.micPermissionGranted().catchError((Object _) => false),
    ]);
    if (!mounted) return;
    setState(() {
      _internet = results[0];
      _mic = results[1];
    });
  }

  /// The 1080p30 profile, if the camera offers it.
  static CaptureProfile? _hd(List<CaptureProfile> profiles) =>
      profiles.where((p) => p.height >= 1080 && p.fps == 30).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final session = ref.watch(cameraSessionProvider);
    final controller = ref.watch(broadcastControllerProvider);
    final info = ref.watch(broadcastInfoProvider).value ?? controller.info;
    if (info.active && !widget.inPage) return const SizedBox.shrink();

    final profile = session.profile;
    final hd = _hd(session.profiles);
    final plugged = session.stats?.plugged;
    // Where the stream goes: the YouTube account while signed in (it wins over a stored key; its
    // own key is set when going live), else the pasted stream key. The line says which one. The
    // account without a session (not restored yet) asks to sign in.
    final view = ref.watch(youtubeAccountViewProvider).value;
    final accountMode = view != null && view.active;
    final email = accountMode ? view.email : null;
    final channel = email == null ? null : view?.channel;
    final destinationOk = accountMode ? email != null : info.configured;
    final items = <_Item>[
      _Item(
        key: 'key',
        ok: destinationOk,
        label: youtubeDestinationLine(
          l10n,
          account: accountMode,
          email: email,
          channel: channel?.title,
          keyConfigured: info.configured,
        ),
        sub: channel == null ? null : email,
        action: destinationOk || widget.inPage ? null : l10n.checkKeyAction,
        onAction: () async {
          final result = await showBroadcastConfigDialog(context, info, youtube: ref.read(youtubeAccountProvider));
          if (result == null) return;
          await controller.configure(
            server: result.server,
            key: result.key,
            targetKbps: result.targetKbps,
            audio: result.audio,
            replayScoreboard: result.replayScoreboard,
          );
          unawaited(_recheck());
        },
      ),
      _Item(
        key: 'quality',
        ok: profile != null && profile.height >= 1080,
        label: profile == null
            ? l10n.checkQualityUnknown
            : profile.height >= 1080
                ? l10n.checkQualityOk(profile.id)
                : l10n.checkQualityLow(profile.id),
        action: profile != null && profile.height < 1080 && hd != null && !info.active ? l10n.checkQualityAction : null,
        onAction: () => ref.read(cameraSessionProvider.notifier).selectProfile(hd!.id),
      ),
      _Item(
        key: 'internet',
        ok: _internet ?? false,
        pending: _internet == null,
        label: switch (_internet) {
          true => l10n.checkInternetOk,
          false => l10n.checkInternetMissing,
          null => l10n.checkInternetChecking,
        },
      ),
      _Item(
        key: 'power',
        ok: plugged ?? false,
        pending: plugged == null,
        label: plugged ?? false ? l10n.checkPowerOk : l10n.checkPowerMissing,
      ),
      if (info.audio)
        _Item(
          key: 'mic',
          ok: _mic ?? false,
          pending: _mic == null,
          label: _mic ?? false ? l10n.checkMicOk : l10n.checkMicMissing,
          action: _mic == false ? l10n.checkMicAction : null,
          onAction: () async {
            await ref.read(captureLayerProvider).requestMicPermission().catchError((Object _) => false);
            unawaited(_recheck());
          },
        ),
    ];
    final ready = items.every((i) => i.ok);
    if (ready && !widget.inPage) return const SizedBox.shrink();
    final shown = widget.inPage ? items : [for (final i in items) if (!i.ok) i];

    final rows = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, item) in shown.indexed)
        Container(
          key: ValueKey('check-${item.key}'),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line))),
          child: Row(children: [
            _Mark(ok: item.ok, pending: item.pending),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: item.ok || item.pending ? c.text : c.warnText,
                    ),
                  ),
                  if (item.sub case final sub?)
                    Text(
                      sub,
                      key: ValueKey('check-${item.key}-sub'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                ],
              ),
            ),
            if (item.action != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: ValueKey('check-${item.key}-action'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 48),
                  foregroundColor: c.signal,
                  side: BorderSide(color: c.signal),
                  textStyle: const TextStyle(fontFamily: IrFonts.sans, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: item.onAction,
                child: Text(item.action!),
              ),
            ],
          ]),
        ),
    ]);

    if (widget.inPage) {
      return Container(
        key: const Key('broadcast-checklist'),
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
        child: rows,
      );
    }

    return Container(
      key: const Key('broadcast-checklist'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(l10n.checkTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        ),
        Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))), child: rows),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text(l10n.camAmberHint, style: TextStyle(fontSize: 13, color: c.muted)),
        ),
      ]),
    );
  }
}

/// A round mark: green check, amber warning, or a muted dot while it is being checked.
class _Mark extends StatelessWidget {
  const _Mark({required this.ok, required this.pending});

  final bool ok;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final color = pending ? c.lineStrong : (ok ? c.ok : c.warn);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        pending ? Icons.more_horiz : (ok ? Icons.check : Icons.priority_high),
        size: 16,
        color: c.bg,
      ),
    );
  }
}

class _Item {
  const _Item({
    required this.key,
    required this.ok,
    required this.label,
    this.sub,
    this.pending = false,
    this.action,
    this.onAction,
  });

  final String key;
  final bool ok;
  final bool pending;
  final String label;

  /// A small muted line under [label] (the account's email under its channel).
  final String? sub;
  final String? action;
  final VoidCallback? onAction;
}
