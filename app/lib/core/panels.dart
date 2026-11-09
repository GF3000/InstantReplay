import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferences.dart';

/// Parts of a screen the user can hide, so one device does only its job: the Camera operator
/// keeps the score, or a bench tablet only reviews replays (SPEC §12.4). Remembered per device.
enum Panel {
  /// Camera, broadcast mode: the scoreboard controls on the phone itself.
  cameraScoreboard,

  /// Viewer: the live view.
  viewerLive,

  /// Viewer, broadcast mode: the scoreboard controls.
  viewerScoreboard,

  /// Viewer: Save, the clip list and the tags.
  viewerReplays,
}

/// The panels hidden on this device; everything is shown by default.
final hiddenPanelsProvider = NotifierProvider<HiddenPanelsNotifier, Set<Panel>>(HiddenPanelsNotifier.new);

class HiddenPanelsNotifier extends Notifier<Set<Panel>> {
  static const _key = 'ui.hiddenPanels';

  @override
  Set<Panel> build() {
    final names = ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    final byName = Panel.values.asNameMap();
    return {for (final n in names) ?byName[n]};
  }

  void toggle(Panel panel) => set(panel, visible: state.contains(panel));

  void set(Panel panel, {required bool visible}) {
    final next = {...state};
    visible ? next.remove(panel) : next.add(panel);
    state = next;
    ref.read(sharedPreferencesProvider).setStringList(_key, [for (final p in next) p.name]);
  }
}

/// Whether [panel] is shown on this device.
final panelShownProvider = Provider.family<bool, Panel>((ref, panel) => !ref.watch(hiddenPanelsProvider).contains(panel));
