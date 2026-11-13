import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_capture_android/replay_capture_android.dart' show CaptureProfile;

import '../../l10n/app_localizations.dart';
import '../broadcast/broadcast_providers.dart';
import '../broadcast/broadcast_widgets.dart';
import '../broadcast/preflight.dart';
import 'camera_session.dart';
import 'capture_layer.dart';
import '../broadcast/youtube/youtube_providers.dart';

/// What to check before going live (SPEC §12.7): stream key, 1080p, Internet, charging and the
/// microphone, each with the fix at hand. Shown while something is missing and the stream is
/// off; it disappears once everything is green.
class BroadcastChecklist extends ConsumerStatefulWidget {
  const BroadcastChecklist({super.key});

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
    final session = ref.watch(cameraSessionProvider);
    final controller = ref.watch(broadcastControllerProvider);
    final info = ref.watch(broadcastInfoProvider).value ?? controller.info;
    if (info.active) return const SizedBox.shrink();

    final profile = session.profile;
    final hd = _hd(session.profiles);
    final plugged = session.stats?.plugged;
    final items = <_Item>[
      _Item(
        key: 'key',
        ok: info.configured,
        label: info.configured ? l10n.checkKeyOk : l10n.checkKeyMissing,
        action: info.configured ? null : l10n.checkKeyAction,
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
        action: profile != null && profile.height < 1080 && hd != null ? l10n.checkQualityAction : null,
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
    if (items.every((i) => i.ok)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      key: const Key('broadcast-checklist'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.checkTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final item in items)
            Row(key: ValueKey('check-${item.key}'), children: [
              Icon(
                item.pending
                    ? Icons.more_horiz
                    : item.ok
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                size: 20,
                color: item.pending
                    ? theme.colorScheme.onSurfaceVariant
                    : item.ok
                        ? Colors.green
                        : theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(item.label, style: theme.textTheme.bodyMedium)),
              if (item.action != null)
                TextButton(
                  key: ValueKey('check-${item.key}-action'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
                  onPressed: item.onAction,
                  child: Text(item.action!),
                )
              else
                const SizedBox(height: 40),
            ]),
        ]),
      ),
    );
  }
}

class _Item {
  const _Item({
    required this.key,
    required this.ok,
    required this.label,
    this.pending = false,
    this.action,
    this.onAction,
  });

  final String key;
  final bool ok;
  final bool pending;
  final String label;
  final String? action;
  final VoidCallback? onAction;
}
