// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'InstantReplay';

  @override
  String get roleGateTitle => 'Choose a role';

  @override
  String get roleGateSubtitle =>
      'This device will remember it. You can switch later.';

  @override
  String get roleCamera => 'Camera';

  @override
  String get roleCameraDescription =>
      'Records the game and keeps the replay buffer.';

  @override
  String get roleViewer => 'Viewer';

  @override
  String get roleViewerDescription => 'Watches live and saves the plays.';

  @override
  String get labEntry => 'Lab (Phase 0 harness)';

  @override
  String get labUnavailable => 'The lab is only available on Android.';

  @override
  String get switchRole => 'Switch role';

  @override
  String get cameraComingSoon => 'The Camera screen arrives in M3.';

  @override
  String get viewerComingSoon => 'The Viewer screen arrives in M4.';
}
