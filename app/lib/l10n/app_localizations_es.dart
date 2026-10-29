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

  @override
  String get viewerConnectTitle => 'Conectar con la cámara';

  @override
  String get viewerAddressLabel => 'Dirección de la cámara';

  @override
  String get viewerAddressInvalid =>
      'Escribe una dirección como http://192.168.1.20:8080';

  @override
  String get viewerAddressSubmit => 'Continuar';

  @override
  String get viewerCodeTitle => 'Escribe el código que muestra la cámara';

  @override
  String viewerCameraAt(String address) {
    return 'Cámara en $address';
  }

  @override
  String get viewerCodeLabel => 'Código de 6 dígitos';

  @override
  String get viewerCodeSubmit => 'Conectar';

  @override
  String get viewerCodeWrong =>
      'Código incorrecto. Revisa la pantalla de la cámara e inténtalo de nuevo.';

  @override
  String get viewerCodeTooManyAttempts =>
      'Demasiados intentos. Espera un minuto e inténtalo de nuevo.';

  @override
  String get viewerCameraUnreachable =>
      'No se puede conectar con la cámara. Comprueba que ambos dispositivos están en la misma Wi-Fi.';

  @override
  String get viewerSessionExpired =>
      'La cámara inició una sesión nueva. Escribe su nuevo código.';

  @override
  String get viewerChangeCamera => 'Cambiar de cámara';

  @override
  String get viewerLinkConnecting => 'Conectando…';

  @override
  String get viewerLinkReconnecting => 'Reconectando…';

  @override
  String get viewerLinkIncompatible =>
      'Esta cámara usa otra versión de InstantReplay. Actualiza ambos dispositivos.';

  @override
  String get viewerLiveStarting => 'Iniciando el directo…';

  @override
  String get viewerLiveInterrupted => 'Directo interrumpido. Reiniciando…';

  @override
  String get viewerLiveRestart => 'Reiniciar el directo';

  @override
  String get viewerStatusRec => 'REC';

  @override
  String get viewerStatusIdle => 'Sin grabar';

  @override
  String viewerStatusFps(int fps) {
    return '$fps fps';
  }

  @override
  String viewerStatusBuffer(int seconds) {
    return 'búfer $seconds s';
  }

  @override
  String viewerStatusOutbox(int clips) {
    return 'pendientes $clips';
  }

  @override
  String viewerStatusTemperature(String celsius) {
    return '$celsius °C';
  }

  @override
  String viewerStatusBattery(int percent, String charging) {
    return '$percent%$charging';
  }

  @override
  String viewerSave(int seconds) {
    return 'GUARDAR $seconds s';
  }

  @override
  String viewerSaveQuick(int seconds) {
    return '$seconds s';
  }

  @override
  String viewerSaveHint(int seconds) {
    return 'Guarda los últimos segundos más $seconds s tras pulsar.';
  }

  @override
  String get viewerSessionOnlyNotice =>
      'Los clips solo se guardan en esta pestaña. Descarga los que quieras conservar.';

  @override
  String get viewerClipsEmpty => 'Los clips guardados aparecen aquí.';

  @override
  String viewerClipTitle(int number, int seconds) {
    return 'Clip $number · $seconds s';
  }

  @override
  String get viewerClipRequesting => 'Solicitando…';

  @override
  String get viewerClipRecording => 'Grabando…';

  @override
  String get viewerClipDownloadingStarted => 'Descargando…';

  @override
  String viewerClipDownloading(int percent) {
    return 'Descargando… $percent%';
  }

  @override
  String get viewerClipReady => 'Listo';

  @override
  String get viewerClipFailedRequest => 'La cámara no respondió';

  @override
  String get viewerClipFailedDownload => 'Falló la descarga';

  @override
  String get viewerClipFailedChecksum => 'La descarga llegó dañada';

  @override
  String get viewerClipExpired => 'Caducó en la cámara';

  @override
  String get viewerClipRetry => 'Reintentar';

  @override
  String get viewerClipDownload => 'Descargar';

  @override
  String get viewerReviewPrevFrame => 'Fotograma anterior';

  @override
  String get viewerReviewNextFrame => 'Fotograma siguiente';

  @override
  String get viewerReviewPlay => 'Reproducir';

  @override
  String get viewerReviewPause => 'Pausa';

  @override
  String viewerReviewSpeed(double speed) {
    final intl.NumberFormat speedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String speedString = speedNumberFormat.format(speed);

    return '$speedString×';
  }

  @override
  String get viewerReviewError => 'Este clip no se puede reproducir aquí.';
}
