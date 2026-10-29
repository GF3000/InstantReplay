import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What this platform can do (SPEC §6). Native Android runs both roles; web is a reduced Viewer.
@immutable
class Capabilities {
  const Capabilities({
    required this.canCapture,
    required this.canExportToGallery,
    required this.canShare,
    required this.hasPersistentLibrary,
    required this.canBeDiscoveredOverNsd,
    required this.canBrowseNsd,
    required this.canEditClips,
    required this.canChangeCameraSettings,
  });

  /// Can run the Camera role (Camera2 capture plugin).
  final bool canCapture;
  final bool canExportToGallery;
  final bool canShare;

  /// Library survives restarts (drift). On web, storage is the current session only (IndexedDB).
  final bool hasPersistentLibrary;

  /// Can announce itself over NSD (Camera role).
  final bool canBeDiscoveredOverNsd;

  /// Can find cameras over NSD; web relies on QR, code or same-origin.
  final bool canBrowseNsd;

  /// Trim and telestrator.
  final bool canEditClips;

  /// Remote camera settings from the Viewer.
  final bool canChangeCameraSettings;

  static const nativeAndroid = Capabilities(
    canCapture: true,
    canExportToGallery: true,
    canShare: true,
    hasPersistentLibrary: true,
    canBeDiscoveredOverNsd: true,
    canBrowseNsd: true,
    canEditClips: true,
    canChangeCameraSettings: true,
  );

  static const web = Capabilities(
    canCapture: false,
    canExportToGallery: false,
    canShare: false,
    hasPersistentLibrary: false,
    canBeDiscoveredOverNsd: false,
    canBrowseNsd: false,
    canEditClips: false,
    canChangeCameraSettings: false,
  );

  /// Unsupported platforms (desktop) get the reduced web set.
  static Capabilities get current =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? nativeAndroid : web;
}

final capabilitiesProvider = Provider<Capabilities>((ref) => Capabilities.current);
