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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(l10n.roleGateTitle, style: text.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(l10n.roleGateSubtitle, style: text.bodyLarge, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (caps.canCapture) ...[
                  _RoleButton(
                    icon: Icons.videocam,
                    label: l10n.roleCamera,
                    description: l10n.roleCameraDescription,
                    onPressed: () => choose(AppRole.camera),
                  ),
                  const SizedBox(height: 16),
                ],
                _RoleButton(
                  icon: Icons.live_tv,
                  label: l10n.roleViewer,
                  description: l10n.roleViewerDescription,
                  onPressed: () => choose(AppRole.viewer),
                ),
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
        ),
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
