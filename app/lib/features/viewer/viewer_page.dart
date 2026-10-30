import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../library/library_providers.dart';
import '../library/presentation/library_page.dart';
import '../library/presentation/session_picker_view.dart';
import '../role/role.dart';
import 'data/session_link.dart';
import 'tags/tag_editor_page.dart';
import 'ui/camera_status.dart';
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
    final library = ref.watch(libraryEnabledProvider);
    final session = ref.watch(activeSessionProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: setup.paired ? 48 : null,
        title: Text(
          camera == null ? l10n.roleViewer : _cameraTitle(camera.name, camera.profileId),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (setup.paired) const CameraStatusIndicator(),
          PopupMenuButton<_MenuItem>(
            key: const ValueKey('viewer-menu'),
            icon: const Icon(Icons.more_vert),
            onSelected: (item) async {
              switch (item) {
                case _MenuItem.tags:
                  await Navigator.of(context).push(TagEditorPage.route());
                case _MenuItem.library:
                  await Navigator.of(context).push(LibraryPage.route());
                case _MenuItem.changeSession:
                  ref.read(activeSessionProvider.notifier).close();
                case _MenuItem.changeCamera:
                  await ref.read(viewerSetupProvider.notifier).changeCamera();
                case _MenuItem.switchRole:
                  await ref.read(roleProvider.notifier).clear();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (_) => [
              // Android edits the tags of the session's template, so it needs a session first.
              if (!library || session != null)
                PopupMenuItem(
                  value: _MenuItem.tags,
                  child: ListTile(leading: const Icon(Icons.sell_outlined), title: Text(l10n.viewerTagsEdit)),
                ),
              if (library)
                PopupMenuItem(
                  value: _MenuItem.library,
                  child: ListTile(leading: const Icon(Icons.video_library_outlined), title: Text(l10n.libraryTitle)),
                ),
              if (library && session != null)
                PopupMenuItem(
                  value: _MenuItem.changeSession,
                  child: ListTile(leading: const Icon(Icons.event_note), title: Text(l10n.libraryChangeSession)),
                ),
              if (setup.paired && !setup.addressFixed)
                PopupMenuItem(
                  value: _MenuItem.changeCamera,
                  child: ListTile(leading: const Icon(Icons.link_off), title: Text(l10n.viewerChangeCamera)),
                ),
              PopupMenuItem(
                value: _MenuItem.switchRole,
                child: ListTile(leading: const Icon(Icons.swap_horiz), title: Text(l10n.switchRole)),
              ),
            ],
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

enum _MenuItem { tags, library, changeSession, changeCamera, switchRole }

class _Session extends ConsumerWidget {
  const _Session();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(linkStateProvider.select((s) => s?.phase));
    // Android: clips go into a library session, picked before the live screen (SPEC §5.1.3).
    if (ref.watch(libraryEnabledProvider)) {
      if (ref.watch(activeSessionProvider) == null) return const SessionPickerView();
      ref.watch(liveLibrarySyncProvider);
    }
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
