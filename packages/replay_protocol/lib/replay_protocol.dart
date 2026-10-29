/// Messages and API types shared by the InstantReplay Camera and Viewer roles.
///
/// Pure Dart: no Flutter or platform imports, so it runs on Android, web and the test VM.
library;

/// Bumped on any breaking change to the REST API or WebSocket messages (SPEC §4).
const int protocolVersion = 1;

/// DNS-SD service type the Camera announces (SPEC §4).
const String serviceType = '_instantreplay._tcp';
