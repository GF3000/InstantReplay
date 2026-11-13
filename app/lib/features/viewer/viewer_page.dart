import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ir_colors.dart';
import '../../l10n/app_localizations.dart';
import '../library/library_providers.dart';
import '../library/presentation/library_page.dart';
import '../library/presentation/session_picker_view.dart';
import '../role/confirm_switch_role.dart';
import '../role/role.dart';
import 'data/session_link.dart';
import '../camera/clip_reserve_widgets.dart';
import 'tags/tag_editor_page.dart';
import 'ui/camera_status.dart';
import 'ui/connect_view.dart';
import 'ui/live_control_view.dart';
import 'viewer_providers.dart';

/// Viewer role (SPEC §5, §6): connect to a Camera, watch live, save and review clips.
///
/// Top bar while paired: the camera's name over the session / teams, the camera-status pill, the
/// stream's mic (broadcast mode) and one menu button with every other action in a sheet. It fits
/// 360 dp; wide screens also get Library and Settings as direct buttons.
class ViewerPage extends ConsumerWidget {
  const ViewerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final setup = ref.watch(viewerSetupProvider);
    final camera = setup.paired ? ref.watch(linkStateProvider.select((s) => s?.camera)) : null;
    final library = ref.watch(libraryEnabledProvider);
    final session = ref.watch(activeSessionProvider);
    final teams = setup.paired
        ? ref.watch(viewerScoreboardProvider.select((s) => s == null ? null : (s.home.name, s.away.name)))
        : null;
    final subtitle = [
      ?camera?.profileId,
      ?session?.name,
      if (teams case (final home, final away)) l10n.liveTeams(home, away),
    ].join(' · ');
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final menu = IconButton(
      key: const ValueKey('viewer-menu'),
      tooltip: l10n.liveMenu,
      icon: const Icon(Icons.menu),
      onPressed: () => _openMenu(context, ref),
    );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: setup.paired ? 56 : null,
        titleSpacing: 16,
        title: camera == null
            ? Text(l10n.roleViewer, overflow: TextOverflow.ellipsis)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  camera.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, height: 1.1, fontWeight: FontWeight.w700),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    key: const ValueKey('viewer-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.muted),
                  ),
              ]),
        actions: [
          if (setup.paired) ...[
            const CameraStatusIndicator(),
            const SizedBox(width: 6),
            ViewerMicButton(labelled: wide),
            if (wide && library)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: OutlinedButton(
                  key: const ValueKey('viewer-library'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44), side: BorderSide(color: c.line)),
                  onPressed: () => Navigator.of(context).push(LibraryPage.route()),
                  child: Text(l10n.libraryTitle),
                ),
              ),
            if (wide)
              IconButton(
                key: const ValueKey('viewer-settings'),
                tooltip: l10n.settingsTitle,
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/viewer/settings'),
              ),
          ] else
            IconButton(
              key: const ValueKey('viewer-settings'),
              tooltip: l10n.settingsTitle,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push('/viewer/settings'),
            ),
          menu,
          const SizedBox(width: 4),
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

  /// Every action of the screen in one sheet; the panel switches act in place, the rest close it.
  Future<void> _openMenu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final item = await showModalBottomSheet<_MenuItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const _MenuSheet(),
    );
    if (item == null || !context.mounted) return;
    switch (item) {
      case _MenuItem.tags:
        await Navigator.of(context).push(TagEditorPage.route());
      case _MenuItem.library:
        await Navigator.of(context).push(LibraryPage.route());
      case _MenuItem.changeSession:
        ref.read(activeSessionProvider.notifier).close();
      case _MenuItem.recording:
        openViewerRecording(context, ref);
      case _MenuItem.clipReserve:
        await showDialog<void>(context: context, builder: (_) => const _ClipReserveDialog());
      case _MenuItem.changeCamera:
        await ref.read(viewerSetupProvider.notifier).changeCamera();
      case _MenuItem.settings:
        await context.push('/viewer/settings');
      case _MenuItem.switchRole:
        // Connected: switching drops the live view and, on Android, the clip transfers.
        final connected = ref.read(linkStateProvider)?.phase == LinkPhase.connected;
        if (connected && !await confirmSwitchRole(context, l10n.switchRoleViewerBody)) return;
        await ref.read(roleProvider.notifier).clear();
        if (context.mounted) context.go('/');
    }
  }
}

enum _MenuItem { tags, library, changeSession, recording, clipReserve, changeCamera, settings, switchRole }

class _MenuSheet extends ConsumerWidget {
  const _MenuSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final setup = ref.watch(viewerSetupProvider);
    final library = ref.watch(libraryEnabledProvider);
    final session = ref.watch(activeSessionProvider);
    final recording = setup.paired ? ref.watch(sessionRecordingProvider) : null;
    final recordingEnabled = ref.watch(linkStateProvider.select(
      (s) => s?.phase == LinkPhase.connected && (s?.status?.recording ?? false),
    ));
    final reserve = setup.paired ? ref.watch(viewerClipReserveProvider) : null;
    Widget entry(_MenuItem item, IconData icon, String label, {String? key, bool enabled = true}) => ListTile(
          key: key == null ? null : ValueKey(key),
          minTileHeight: 56,
          enabled: enabled,
          leading: Icon(icon),
          title: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.of(context).pop(item),
        );
    Widget section(String label) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Text(label.toUpperCase(), style: irMono(12, weight: FontWeight.w600, color: c.muted)),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Android edits the tags of the session's template, so it needs a session first.
          if (!library || session != null)
            entry(_MenuItem.tags, Icons.sell_outlined, l10n.viewerTagsEdit, key: 'viewer-menu-tags'),
          if (library) entry(_MenuItem.library, Icons.video_library_outlined, l10n.libraryTitle, key: 'viewer-menu-library'),
          if (library && session != null)
            entry(_MenuItem.changeSession, Icons.event_note, l10n.libraryChangeSession, key: 'viewer-menu-change-session'),
          if (recording != null)
            entry(_MenuItem.recording, Icons.videocam_outlined, l10n.recTitle,
                key: 'viewer-menu-recording', enabled: recordingEnabled),
          if (reserve != null)
            entry(_MenuItem.clipReserve, Icons.inventory_2_outlined, l10n.clipReserveTitle, key: 'viewer-menu-clip-reserve'),
          if (setup.paired) ...[
            const Divider(height: 1),
            section(l10n.panelsTitle),
            const ViewerPanelToggles(),
            const Divider(height: 1),
          ],
          if (setup.paired && !setup.addressFixed)
            entry(_MenuItem.changeCamera, Icons.link_off, l10n.viewerChangeCamera, key: 'viewer-menu-change-camera'),
          entry(_MenuItem.settings, Icons.settings_outlined, l10n.settingsTitle, key: 'viewer-menu-settings'),
          entry(_MenuItem.switchRole, Icons.swap_horiz, l10n.switchRole, key: 'viewer-menu-switch-role'),
        ]),
      ),
    );
  }
}

/// The Camera's replay reserve, changed from this viewer; the value follows the Camera's status.
class _ClipReserveDialog extends ConsumerWidget {
  const _ClipReserveDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final size = ref.watch(viewerClipReserveProvider);
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    return AlertDialog(
      title: Text(l10n.clipReserveTitle),
      // Compact: the number between − and +, the explanation below; the dialog sizes to it.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: ClipReserveStepper(
          keyPrefix: 'viewer-clip-reserve',
          vertical: true,
          size: size ?? 0,
          enabled: connected && size != null,
          onChanged: ref.read(viewerBroadcastNoticeProvider.notifier).reserve,
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.clipReserveDone),
        ),
      ],
    );
  }
}

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
