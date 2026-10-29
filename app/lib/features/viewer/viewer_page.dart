import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../role/role.dart';
import 'data/session_link.dart';
import 'ui/connect_view.dart';
import 'ui/live_control_view.dart';
import 'viewer_providers.dart';

/// Viewer role (SPEC §5, §6): connect to a Camera, watch live, save and review clips.
class ViewerPage extends ConsumerWidget {
  const ViewerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final setup = ref.watch(viewerSetupProvider);
    final camera = setup.paired ? ref.watch(linkStateProvider.select((s) => s?.camera)) : null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: setup.paired ? 48 : null,
        title: Text(camera == null ? l10n.roleViewer : _cameraTitle(camera.name, camera.profileId)),
        actions: [
          if (setup.paired && !setup.addressFixed)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: l10n.viewerChangeCamera,
              onPressed: () => ref.read(viewerSetupProvider.notifier).changeCamera(),
            ),
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
      body: SafeArea(
        child: switch (setup) {
          ViewerSetup(base: null) => const AddressForm(),
          ViewerSetup(token: null) => const PairForm(),
          _ => const _Session(),
        },
      ),
    );
  }

  static String _cameraTitle(String name, String? profile) => profile == null ? name : '$name · $profile';
}

class _Session extends ConsumerWidget {
  const _Session();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(linkStateProvider.select((s) => s?.phase));
    if (phase == LinkPhase.incompatible) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(context).viewerLinkIncompatible,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return const LiveControlView();
  }
}
