import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/capabilities.dart';
import '../../core/ui/bucle_logo.dart';
import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'role.dart';

class RoleGatePage extends ConsumerWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final caps = ref.watch(capabilitiesProvider);
    final c = context.ir;

    Future<void> choose(AppRole role) async {
      await ref.read(roleProvider.notifier).select(role);
      if (context.mounted) context.go('/${role.name}');
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          // Landscape (a phone on its side, a tablet): Camera | Viewer side by side, so all three
          // fit without scrolling; portrait: one above the other.
          final wide = caps.canCapture && box.maxWidth > box.maxHeight && box.maxWidth >= 600;
          final camera = _RoleKey(
            key: const ValueKey('role-camera'),
            icon: Icons.videocam,
            label: l10n.roleCamera,
            description: l10n.roleCameraDescription,
            compact: wide,
            onPressed: () => choose(AppRole.camera),
          );
          final viewer = _RoleKey(
            key: const ValueKey('role-viewer'),
            icon: Icons.live_tv,
            label: l10n.roleViewer,
            description: l10n.roleViewerDescription,
            compact: wide,
            onPressed: () => choose(AppRole.viewer),
          );
          // Smaller on purpose: most sessions are replays; streaming is one tap away.
          final broadcast = IrKey(
            key: const ValueKey('role-broadcast'),
            led: c.live,
            minHeight: 60,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            onPressed: () => choose(AppRole.broadcast),
            child: Row(children: [
              Icon(Icons.sensors, size: 26, color: c.liveText),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    l10n.roleBroadcastEntry,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
                  ),
                  Text(
                    l10n.roleBroadcastDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted),
                  ),
                ]),
              ),
            ]),
          );
          final header = _Header(compact: wide);

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 900 : 480),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 18, vertical: wide ? 12 : 24),
                children: [
                  header,
                  SizedBox(height: wide ? 16 : 28),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: camera),
                        const SizedBox(width: 12),
                        Expanded(child: viewer),
                      ]),
                    )
                  else ...[
                    if (caps.canCapture) ...[camera, const SizedBox(height: 12)],
                    viewer,
                  ],
                  if (caps.canCapture) ...[SizedBox(height: wide ? 12 : 20), broadcast],
                  if (kDebugMode && caps.canCapture) ...[
                    const SizedBox(height: 16),
                    Align(
                      child: TextButton.icon(
                        icon: const Icon(Icons.science),
                        label: Text(l10n.labEntry),
                        onPressed: () => context.push('/lab'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Logo and app name, then what to do. Landscape puts the name beside the logo to save height.
class _Header extends StatelessWidget {
  const _Header({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final name = Text(l10n.appTitle, style: TextStyle(fontSize: compact ? 22 : 26, fontWeight: FontWeight.w700, color: c.text));
    final title = Text(
      l10n.roleGateTitle,
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: TextStyle(fontSize: compact ? 18 : 22, fontWeight: FontWeight.w600, color: c.text),
    );
    final subtitle = Text(
      l10n.roleGateSubtitle,
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted),
    );
    if (compact) {
      return Row(children: [
        const BucleLogo(size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              name,
              const SizedBox(width: 12),
              Flexible(child: title),
            ]),
            subtitle,
          ]),
        ),
      ]);
    }
    return Column(children: [
      const BucleLogo(size: 72),
      const SizedBox(height: 12),
      name,
      const SizedBox(height: 20),
      title,
      const SizedBox(height: 6),
      subtitle,
    ]);
  }
}

/// A role as a big hardware key: icon, name and what the device does in that role.
class _RoleKey extends StatelessWidget {
  const _RoleKey({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final minHeight = compact ? 96.0 : 104.0;
    return IrKey(
      onPressed: onPressed,
      minHeight: minHeight,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      // IrKey top-aligns its child: a Row as tall as the key centres the content.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight - 28),
        child: Row(children: [
          Icon(icon, size: 40, color: c.signal),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(fontSize: 22, height: 1.1, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text(description, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
