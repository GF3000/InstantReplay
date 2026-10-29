// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'InstantReplay';

  @override
  String get roleGateTitle => 'Elige un rol';

  @override
  String get roleGateSubtitle =>
      'Este dispositivo lo recordará. Puedes cambiarlo después.';

  @override
  String get roleCamera => 'Cámara';

  @override
  String get roleCameraDescription =>
      'Graba el partido y mantiene el búfer de repetición.';

  @override
  String get roleViewer => 'Visor';

  @override
  String get roleViewerDescription => 'Ve en directo y guarda las jugadas.';

  @override
  String get labEntry => 'Laboratorio (banco de pruebas Fase 0)';

  @override
  String get labUnavailable =>
      'El laboratorio solo está disponible en Android.';

  @override
  String get switchRole => 'Cambiar de rol';

  @override
  String get cameraComingSoon => 'La pantalla de Cámara llega en M3.';

  @override
  String get viewerComingSoon => 'La pantalla de Visor llega en M4.';
}
