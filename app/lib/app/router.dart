import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/capabilities.dart';
import '../features/camera/camera_page.dart';
import '../features/lab/lab_page.dart';
import '../features/role/role.dart';
import '../features/role/role_gate_page.dart';
import '../features/settings/settings_page.dart';
import '../features/viewer/viewer_page.dart';

/// Role screens replace each other (`go`): a short cross-fade, not a slide that suggests "back".
Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: CurveTween(curve: Curves.easeOut).animate(animation), child: child),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', pageBuilder: (_, state) => _fade(state, const RoleGatePage())),
      GoRoute(path: '/camera', pageBuilder: (_, state) => _fade(state, const CameraPage())),
      // The same Camera screen; the session reads the role to start in broadcast mode.
      GoRoute(path: '/broadcast', pageBuilder: (_, state) => _fade(state, const CameraPage())),
      GoRoute(
        path: '/viewer',
        pageBuilder: (_, state) => _fade(state, const ViewerPage()),
        // Pushed on top: the platform's own transition, with a back gesture.
        routes: [GoRoute(path: 'settings', builder: (_, _) => const SettingsPage())],
      ),
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
        '/camera' || '/broadcast' when !caps.canCapture => '/',
        '/lab' when !(kDebugMode && caps.canCapture) => '/',
        _ => null,
      };
    },
  );
  ref.onDispose(router.dispose);
  return router;
});
