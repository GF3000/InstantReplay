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
  String get viewerComingSoon => 'La pantalla de Visor llega en M4.';

  @override
  String get cameraStarting => 'Iniciando la cámara…';

  @override
  String get cameraPermissionDenied =>
      'InstantReplay necesita permiso de cámara para grabar.';

  @override
  String get cameraNoProfiles =>
      'Este dispositivo no tiene ninguna calidad de grabación compatible.';

  @override
  String cameraStartFailed(String error) {
    return 'No se pudo iniciar la cámara: $error';
  }

  @override
  String get cameraRetry => 'Reintentar';

  @override
  String get cameraProfile => 'Calidad';

  @override
  String get cameraStartOperating => 'Empezar a operar';

  @override
  String get cameraOperatingHint =>
      'Toca en cualquier sitio para volver a la configuración';

  @override
  String cameraOperatingStatus(int seconds, int clips, String temperature) {
    return 'REC · búfer $seconds s · bandeja $clips · $temperature';
  }

  @override
  String get cameraWaitingForStats => 'Esperando estadísticas…';

  @override
  String get cameraStatCamera => 'Cámara';

  @override
  String get cameraStatFps => 'Fotogramas';

  @override
  String cameraFpsValue(String fps) {
    return '$fps fps';
  }

  @override
  String get cameraStatGaps => 'Saltos de fotogramas';

  @override
  String cameraGapsValue(int total, int camera, int gl) {
    return '$total (cámara $camera, GL $gl)';
  }

  @override
  String get cameraStatBuffer => 'Búfer';

  @override
  String cameraBufferValue(int seconds, String megabytes) {
    return '$seconds s · $megabytes MB';
  }

  @override
  String get cameraStatOutbox => 'Bandeja de salida';

  @override
  String cameraOutboxValue(int clips, String megabytes) {
    String _temp0 = intl.Intl.pluralLogic(
      clips,
      locale: localeName,
      other: '$clips clips',
      one: '1 clip',
    );
    return '$_temp0 · $megabytes MB';
  }

  @override
  String get cameraStatThermal => 'Estado térmico';

  @override
  String get cameraStatBattery => 'Batería';

  @override
  String cameraBatteryValue(String temperature, String percent, String power) {
    return '$temperature · $percent · $power';
  }

  @override
  String get cameraCharging => 'cargando';

  @override
  String get cameraNotCharging => 'sin cargar';

  @override
  String get cameraNotChargingWarning =>
      'No está cargando. Conecta la corriente para sesiones largas.';

  @override
  String get cameraNotificationsDenied =>
      'Las notificaciones están desactivadas, así que Android no mostrará el aviso de grabación. La grabación funciona igual.';

  @override
  String get cameraErrorsTitle => 'Errores de cámara';

  @override
  String get cameraDismissErrors => 'Descartar';

  @override
  String get cameraSaveTestClip => 'Guardar clip de prueba (últimos 20 s)';

  @override
  String cameraTestClipSaved(String seconds, String megabytes) {
    return 'Clip de prueba guardado: $seconds s, $megabytes MB';
  }

  @override
  String cameraTestClipFailed(String error) {
    return 'Falló el clip de prueba: $error';
  }

  @override
  String get thermalNone => 'Normal';

  @override
  String get thermalLight => 'Leve';

  @override
  String get thermalModerate => 'Moderado';

  @override
  String get thermalSevere => 'Grave';

  @override
  String get thermalCritical => 'Crítico';

  @override
  String get thermalEmergency => 'Emergencia';

  @override
  String get thermalShutdown => 'Apagado';
}
