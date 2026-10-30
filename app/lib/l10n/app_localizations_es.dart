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
  String get viewerScanQr => 'Escanear QR';

  @override
  String get viewerScanHint => 'Apunta al QR que muestra la cámara';

  @override
  String get viewerScanNotCamera =>
      'Este QR no es de una cámara de InstantReplay. Apunta al QR de la cámara.';

  @override
  String get viewerScanPermissionDenied =>
      'Sin permiso de cámara. Escribe la dirección o permite la cámara en Ajustes.';

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
  String viewerStatusTemperature(String celsius) {
    return '$celsius °C';
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

  @override
  String get cameraPairingTitle => 'Conectar un visor';

  @override
  String get cameraPairingCode => 'Código de emparejamiento';

  @override
  String get cameraPairingScanHint =>
      'Escanea el código QR o abre esta dirección en un navegador en la misma Wi-Fi:';

  @override
  String get cameraPairingNoNetwork =>
      'No hay Wi-Fi ni punto de acceso. Activa el punto de acceso o conéctate a una red Wi-Fi.';

  @override
  String cameraViewersConnected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visores conectados',
      one: '1 visor conectado',
      zero: 'Ningún visor conectado',
    );
    return '$_temp0';
  }

  @override
  String cameraOperatingViewers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visores',
      one: '1 visor',
    );
    return '$_temp0';
  }

  @override
  String get serverStarting => 'Iniciando el servidor para visores…';

  @override
  String serverStartFailed(String error) {
    return 'No se pudo iniciar el servidor para visores: $error';
  }

  @override
  String get viewerStatusTitle => 'Estado de la cámara';

  @override
  String get viewerStatusRecording => 'Grabación';

  @override
  String get viewerStatusFpsLabel => 'Fotogramas por segundo';

  @override
  String get viewerStatusBufferLabel => 'Búfer de repetición';

  @override
  String viewerStatusSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get viewerStatusPendingLabel => 'Clips pendientes en la cámara';

  @override
  String get viewerStatusTemperatureLabel => 'Temperatura';

  @override
  String get viewerStatusBatteryLabel => 'Batería';

  @override
  String viewerStatusBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get viewerStatusCharging => 'cargando';

  @override
  String get viewerStatusNotCharging => 'sin cargar';

  @override
  String get viewerProblemDisconnected => 'Desconectada';

  @override
  String get viewerProblemHot => 'Sobrecalentada';

  @override
  String viewerProblemBatteryLow(int percent) {
    return 'Batería $percent%';
  }

  @override
  String viewerClipName(String tag, String time) {
    return '$tag · $time';
  }

  @override
  String viewerClipUntagged(String time) {
    return 'Clip · $time';
  }

  @override
  String viewerClipDuration(int seconds) {
    return '$seconds s';
  }

  @override
  String get viewerClipChangeTag => 'Etiqueta';

  @override
  String get viewerClipNoTag => 'Sin etiqueta';

  @override
  String get viewerFilterAll => 'Todos';

  @override
  String get viewerTagDefaultGood => 'Bien';

  @override
  String get viewerTagDefaultBad => 'Mal';

  @override
  String get viewerTagDefaultOther => 'Otros';

  @override
  String get viewerTagsEdit => 'Editar etiquetas';

  @override
  String get viewerTagsTitle => 'Etiquetas';

  @override
  String get viewerTagsAdd => 'Añadir etiqueta';

  @override
  String get viewerTagsEmpty =>
      'No hay etiquetas. Añade una para marcar tus clips.';

  @override
  String get viewerTagEdit => 'Editar etiqueta';

  @override
  String get viewerTagName => 'Nombre';

  @override
  String get viewerTagColor => 'Color';

  @override
  String get viewerTagDelete => 'Borrar etiqueta';

  @override
  String get viewerTagCancel => 'Cancelar';

  @override
  String get viewerTagOk => 'Guardar';

  @override
  String get cameraAdvanced => 'Avanzado';

  @override
  String cameraHotWarning(String level) {
    return 'El teléfono está caliente ($level). Ponlo a la sombra o baja la calidad.';
  }

  @override
  String viewerTagDeleted(String name) {
    return '\"$name\" borrada';
  }

  @override
  String get viewerTagUndo => 'Deshacer';

  @override
  String get libraryTitle => 'Biblioteca';

  @override
  String get libraryChangeSession => 'Cambiar sesión';

  @override
  String get librarySessionLatest => 'Última sesión';

  @override
  String get librarySessionContinue => 'Continuar';

  @override
  String get librarySessionNew => 'Nueva sesión';

  @override
  String get librarySessionName => 'Nombre';

  @override
  String librarySessionDefaultName(String type, String date) {
    return '$type $date';
  }

  @override
  String get librarySessionTemplate => 'Plantilla de etiquetas';

  @override
  String get librarySessionStart => 'Empezar sesión';

  @override
  String get librarySessionTypeMatch => 'Partido';

  @override
  String get librarySessionTypeTraining => 'Entrenamiento';

  @override
  String get librarySessionTypeOther => 'Otro';

  @override
  String librarySessionClips(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips',
      one: '1 clip',
      zero: 'sin clips',
    );
    return '$_temp0';
  }

  @override
  String get librarySessionClipsEmpty => 'No hay clips en esta sesión.';

  @override
  String get libraryEmpty => 'Aún no hay sesiones.';

  @override
  String librarySelected(int count) {
    return '$count seleccionados';
  }

  @override
  String get librarySelectAll => 'Seleccionar todo';

  @override
  String get libraryDelete => 'Borrar';

  @override
  String libraryDeleteClipsConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Borrar $count clips? No se puede deshacer.',
      one: '¿Borrar 1 clip? No se puede deshacer.',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteSession => 'Borrar sesión';

  @override
  String libraryDeleteSessionConfirm(String name) {
    return '¿Borrar «$name» y todos sus clips? No se puede deshacer.';
  }

  @override
  String get libraryTemplatesTitle => 'Plantillas de etiquetas';

  @override
  String get libraryTemplateBuiltIn => 'Incluida';

  @override
  String get libraryTemplateExport => 'Copiar como JSON';

  @override
  String get libraryTemplateExported => 'Plantilla copiada al portapapeles';

  @override
  String get libraryTemplateImport => 'Importar JSON';

  @override
  String get libraryTemplateImportHint =>
      'Pega una plantilla exportada desde InstantReplay';

  @override
  String libraryTemplateImported(String name) {
    return '«$name» importada';
  }

  @override
  String libraryTemplateImportError(String reason) {
    return 'No es una plantilla válida: $reason';
  }

  @override
  String get libraryTemplateDelete => 'Borrar plantilla';

  @override
  String get libraryTemplateLabelsTitle => 'Etiquetas y categorías';

  @override
  String get libraryCategoriesTitle => 'Categorías';

  @override
  String get libraryCategory => 'Categoría';

  @override
  String get libraryCategoryAdd => 'Añadir categoría';

  @override
  String get libraryCategoriesEmpty =>
      'No hay categorías. Añade una para agrupar tus clips.';

  @override
  String get libraryTemplateFootball => 'Fútbol';

  @override
  String get libraryTemplateBasketball => 'Baloncesto';

  @override
  String get libraryTemplateHandball => 'Balonmano';

  @override
  String get libraryTemplateHockey => 'Hockey';

  @override
  String get libraryTemplateGeneric => 'Genérica';

  @override
  String get libraryTemplateMigrated => 'Mis etiquetas';

  @override
  String get libraryCategoryAttack => 'Ataque';

  @override
  String get libraryCategoryDefense => 'Defensa';

  @override
  String get libraryCategoryTransition => 'Transición';

  @override
  String get libraryCategorySetPiece => 'Balón parado';

  @override
  String get libraryTagGoal => 'Gol';

  @override
  String get libraryTagShot => 'Tiro';

  @override
  String get libraryTagFoul => 'Falta';

  @override
  String get libraryTagCorner => 'Córner';

  @override
  String get libraryTagFreeKick => 'Tiro libre';

  @override
  String get libraryTagTurnover => 'Pérdida';

  @override
  String get libraryTagBasket => 'Canasta';

  @override
  String get libraryTagThreePointer => 'Triple';

  @override
  String get libraryTagRebound => 'Rebote';

  @override
  String get libraryTagSteal => 'Robo';

  @override
  String get libraryTagSave => 'Parada';

  @override
  String get libraryTagSevenMeters => '7 metros';

  @override
  String get libraryTagPenalty => 'Penalti';
}
