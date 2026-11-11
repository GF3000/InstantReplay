import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities.dart';
import '../../core/preferences.dart';

/// Camera (replays), Viewer, or Broadcast: the Camera streaming the match (SPEC §12.7). The
/// route of each is `/<name>`.
enum AppRole {
  camera,
  viewer,
  broadcast;

  /// Runs the camera pipeline on this device.
  bool get captures => this != viewer;
}

/// The role chosen on this device, or null until the user picks one.
class RoleNotifier extends Notifier<AppRole?> {
  static const _key = 'role';

  /// Before the Broadcast role, broadcast mode was a Camera setting.
  static const _legacyModeKey = 'camera.mode';

  @override
  AppRole? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    var saved = AppRole.values.asNameMap()[prefs.getString(_key)];
    if (prefs.getString(_legacyModeKey) == 'broadcast') {
      // Once: a Camera left in broadcast mode becomes the Broadcast role.
      if (saved == AppRole.camera) {
        saved = AppRole.broadcast;
        prefs.setString(_key, saved.name);
      }
      prefs.remove(_legacyModeKey);
    }
    return saved != null && saved.captures && !ref.watch(capabilitiesProvider).canCapture ? null : saved;
  }

  Future<void> select(AppRole role) async {
    state = role;
    await ref.read(sharedPreferencesProvider).setString(_key, role.name);
  }

  Future<void> clear() async {
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_key);
  }
}

final roleProvider = NotifierProvider<RoleNotifier, AppRole?>(RoleNotifier.new);
