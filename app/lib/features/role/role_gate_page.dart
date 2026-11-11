import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/capabilities.dart';
import '../../l10n/app_localizations.dart';
import 'role.dart';

class RoleGatePage extends ConsumerWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final caps = ref.watch(capabilitiesProvider);
    final text = Theme.of(context).textTheme;

    Future<void> choose(AppRole role) async {
      await ref.read(roleProvider.notifier).select(role);
      if (context.mounted) context.go('/${role.name}');
    }

    final camera = _RoleButton(
      icon: Icons.videocam,
      label: l10n.roleCamera,
      description: l10n.roleCameraDescription,
      onPressed: () => choose(AppRole.camera),
    );
    final viewer = _RoleButton(
      icon: Icons.live_tv,
      label: l10n.roleViewer,
      description: l10n.roleViewerDescription,
      onPressed: () => choose(AppRole.viewer),
    );
    // Smaller on purpose: most sessions are replays; streaming is one tap away.
    final broadcast = OutlinedButton(
      key: const ValueKey('role-broadcast'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        alignment: AlignmentDirectional.centerStart,
      ),
      onPressed: () => choose(AppRole.broadcast),
      child: Row(children: [
        const Icon(Icons.sensors, size: 28, color: Color(0xFFE53935)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.roleBroadcastEntry, style: text.titleMedium),
            Text(l10n.roleBroadcastDescription, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          // Landscape (a phone on its side, a tablet): Camera | Viewer side by side, so all three
          // fit without scrolling; portrait: one above the other.
          final wide = caps.canCapture && c.maxWidth > c.maxHeight && c.maxWidth >= 600;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 900 : 480),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.all(wide ? 16 : 24),
                children: [
                  Text(l10n.roleGateTitle, style: text.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(l10n.roleGateSubtitle, style: text.bodyLarge, textAlign: TextAlign.center),
                  SizedBox(height: wide ? 20 : 32),
                  if (wide)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: camera),
                        const SizedBox(width: 16),
                        Expanded(child: viewer),
                      ]),
                    )
                  else ...[
                    if (caps.canCapture) ...[camera, const SizedBox(height: 16)],
                    viewer,
                  ],
                  if (caps.canCapture) ...[SizedBox(height: wide ? 16 : 24), broadcast],
                  if (kDebugMode && caps.canCapture) ...[
                    const SizedBox(height: 32),
                    TextButton.icon(
                      icon: const Icon(Icons.science),
                      label: Text(l10n.labEntry),
                      onPressed: () => context.push('/lab'),
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

class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.icon, required this.label, required this.description, required this.onPressed});

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(96),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        alignment: AlignmentDirectional.centerStart,
        textStyle: Theme.of(context).textTheme.titleLarge,
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, size: 40),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
