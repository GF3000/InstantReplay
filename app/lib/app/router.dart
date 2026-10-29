import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/capabilities.dart';
import '../features/camera/camera_page.dart';
import '../features/lab/lab_page.dart';
import '../features/role/role.dart';
import '../features/role/role_gate_page.dart';
import '../features/viewer/viewer_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const RoleGatePage()),
      GoRoute(path: '/camera', builder: (_, _) => const CameraPage()),
      GoRoute(path: '/viewer', builder: (_, _) => const ViewerPage()),
      GoRoute(path: '/lab', builder: (_, _) => const LabPage()),
    ],
    redirect: (_, state) {
      final caps = ref.read(capabilitiesProvider);
      return switch (state.matchedLocation) {
        // Without capture (web) the Viewer is the only role: skip the gate, e.g. after a QR scan.
        '/' when !caps.canCapture => '/viewer',
        '/' => switch (ref.read(roleProvider)) {
            null => null,
            final role => '/${role.name}',
          },
        '/camera' when !caps.canCapture => '/',
        '/lab' when !(kDebugMode && caps.canCapture) => '/',
        _ => null,
      };
    },
  );
  ref.onDispose(router.dispose);
  return router;
});
