import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/capabilities.dart';
import '../../core/preferences.dart';

enum AppRole { camera, viewer }

/// The role chosen on this device, or null until the user picks one.
class RoleNotifier extends Notifier<AppRole?> {
  static const _key = 'role';

  @override
  AppRole? build() {
    final saved = AppRole.values.asNameMap()[ref.watch(sharedPreferencesProvider).getString(_key)];
    return saved == AppRole.camera && !ref.watch(capabilitiesProvider).canCapture ? null : saved;
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
