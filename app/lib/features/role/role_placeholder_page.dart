import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'role.dart';

/// Shared scaffold for role screens that are not built yet.
class RolePlaceholderPage extends ConsumerWidget {
  const RolePlaceholderPage({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: l10n.switchRole,
            onPressed: () async {
              await ref.read(roleProvider.notifier).clear();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: IrPanel(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.construction, size: 36, color: context.ir.muted),
                const SizedBox(height: 12),
                Text(message, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
