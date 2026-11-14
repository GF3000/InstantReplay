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
  String get viewerReviewZoomReset => 'Quitar zoom';

  @override
  String get viewerReviewNextFrame => 'Fotograma siguiente';

  @override
  String get viewerDraw => 'Dibujar';

  @override
  String get viewerDrawColor => 'Color';

  @override
  String get viewerDrawUndo => 'Deshacer';

  @override
  String get viewerDrawClear => 'Borrar dibujo';

  @override
  String get viewerDrawDone => 'Listo';

  @override
  String get viewerDrawArrow => 'Flecha';

  @override
  String get viewerDrawCircle => 'Círculo';

  @override
  String get viewerDrawLine => 'Línea recta';

  @override
  String get viewerDrawPen => 'Mano alzada';

  @override
  String get viewerDrawSelect => 'Seleccionar y mover';

  @override
  String get viewerDrawEraser => 'Goma';

  @override
  String get viewerDrawDelete => 'Borrar elemento';

  @override
  String get viewerDrawThick => 'Trazo grueso';

  @override
  String get viewerReviewPrevClip => 'Clip anterior';

  @override
  String get viewerReviewNextClip => 'Clip siguiente';

  @override
  String get viewerReviewPlaylistRestart => 'Volver a ver todos';

  @override
  String viewerReviewPlaylistPosition(int index, int count) {
    return '$index / $count';
  }

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
  String get recTitle => 'Grabación completa';

  @override
  String get recRecord => 'Grabar';

  @override
  String get recResume => 'Reanudar';

  @override
  String get recPause => 'Pausar';

  @override
  String get recFinish => 'Terminar';

  @override
  String get recOptions => 'Opciones de grabación';

  @override
  String get recFromNow => 'Grabar desde ahora';

  @override
  String get recResumeFromNow => 'Reanudar desde ahora';

  @override
  String recIncludeLast(int seconds) {
    return 'Grabar incluyendo los últimos $seconds s';
  }

  @override
  String recResumeIncludeLast(int seconds) {
    return 'Reanudar incluyendo los últimos $seconds s';
  }

  @override
  String get recIdle => 'Sin grabar';

  @override
  String recPaused(String elapsed) {
    return 'En pausa · $elapsed';
  }

  @override
  String recPart(int part) {
    return 'parte $part';
  }

  @override
  String recRemaining(String time) {
    return 'quedan $time';
  }

  @override
  String recLowSpace(String time) {
    return 'Poco espacio: quedan $time';
  }

  @override
  String get recLowSpaceUnknown => 'Poco espacio en la cámara';

  @override
  String recFree(String gigabytes) {
    return '$gigabytes GB libres';
  }

  @override
  String get recFinishTitle => '¿Terminar la grabación?';

  @override
  String recFinishBody(String elapsed) {
    return 'Lo grabado ($elapsed) se guardará en la galería de la cámara (Movies/InstantReplay).';
  }

  @override
  String get recFinishKeep => 'Seguir grabando';

  @override
  String recSaved(int parts, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      parts,
      locale: localeName,
      other:
          'Grabación guardada en la galería de la cámara ($duration, $parts partes)',
      one: 'Grabación guardada en la galería de la cámara ($duration)',
    );
    return '$_temp0';
  }

  @override
  String recSavedLowSpace(String duration) {
    return 'La cámara se quedó sin espacio: la grabación se detuvo y se guardó ($duration)';
  }

  @override
  String recSavedError(String duration) {
    return 'La grabación se detuvo por un error; se ha guardado lo grabado ($duration)';
  }

  @override
  String recRecovered(String duration) {
    return 'Se ha recuperado una grabación de $duration';
  }

  @override
  String get recRecoveredHint =>
      'Quedó abierta al cerrarse la app. Está en la galería (Movies/InstantReplay).';

  @override
  String get recNoSpace =>
      'No hay espacio suficiente en la cámara para grabar (hace falta 1 GB libre)';

  @override
  String recFailed(String message) {
    return 'No se pudo grabar: $message';
  }

  @override
  String get viewerClipSaveToGallery => 'Guardar en la galería';

  @override
  String get viewerClipShare => 'Compartir';

  @override
  String get viewerClipSavedToGallery => 'Guardado en la galería';

  @override
  String get viewerClipGalleryDenied =>
      'Sin permiso para guardar en la galería';

  @override
  String get viewerClipExportNoSpace => 'No queda espacio en el teléfono';

  @override
  String get viewerClipExportFailed => 'No se pudo exportar el clip';

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
  String get libraryExport => 'Exportar';

  @override
  String get libraryExportJoinedGallery => 'Un solo vídeo → galería';

  @override
  String get libraryExportJoinedShare => 'Un solo vídeo → compartir';

  @override
  String get libraryExportZip => 'ZIP con los vídeos por separado';

  @override
  String get libraryExporting => 'Exportando…';

  @override
  String libraryWatchAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver todos ($count)',
      one: 'Ver 1 clip',
    );
    return '$_temp0';
  }

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
  String get libraryTagAttack => 'Ataque';

  @override
  String get libraryTagDefense => 'Defensa';

  @override
  String get libraryTagTransition => 'Transición';

  @override
  String get libraryTagSetPiece => 'Balón parado';

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

  @override
  String get viewerNearbyTitle => 'Cámaras en esta red';

  @override
  String get viewerNearbySearching => 'Buscando cámaras…';

  @override
  String get viewerNearbyIncompatible => 'Otra versión de InstantReplay';

  @override
  String get viewerNearbyOther => 'O conecta de otra forma';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsSaveSection => 'Botón Guardar';

  @override
  String get settingsDefaultDuration => 'Duración por defecto';

  @override
  String get settingsQuickPresets => 'Botones rápidos';

  @override
  String settingsQuickPresetsHint(int max) {
    return 'Elige hasta $max. Cada uno guarda al instante con su duración.';
  }

  @override
  String settingsPostRoll(int seconds) {
    return 'Margen posterior: $seconds s';
  }

  @override
  String get settingsPostRollHint =>
      'Segundos que se siguen grabando tras pulsar Guardar.';

  @override
  String get settingsDisplaySection => 'Pantalla';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsSystem => 'Sistema';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsStorageSection => 'Almacenamiento';

  @override
  String get settingsStorageClips => 'Clips guardados';

  @override
  String settingsStorageUsage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips',
      one: '1 clip',
    );
    return '$size en $_temp0';
  }

  @override
  String get settingsStorageUnavailable => 'No se pudo leer el espacio usado.';

  @override
  String viewerClipDeleted(String name) {
    return '$name borrado';
  }

  @override
  String get viewerClipUndo => 'Deshacer';

  @override
  String get viewerTagPanelTitle => 'Etiqueta la jugada';

  @override
  String get viewerTagPanelClose => 'Cerrar';

  @override
  String get cameraMode => 'Modo';

  @override
  String get cameraModeReplay => 'Repetición';

  @override
  String get cameraModeBroadcast => 'Emisión (beta)';

  @override
  String get cameraModeBroadcastHint =>
      'Experimental: emite en directo a YouTube con un marcador que se controla desde los visores. Los clips siguen funcionando.';

  @override
  String get cameraModeLocked =>
      'Detén la emisión para cambiar el modo o el perfil.';

  @override
  String get broadcastTitle => 'Emisión en YouTube';

  @override
  String get broadcastStateIdle => 'Sin emitir';

  @override
  String get broadcastStateConnecting => 'Conectando…';

  @override
  String get broadcastStateLive => 'En directo';

  @override
  String get broadcastStateReconnecting => 'Reconectando…';

  @override
  String get broadcastStateFailed => 'Error';

  @override
  String get broadcastNotConfigured => 'Introduce primero la clave de emisión';

  @override
  String broadcastReady(int kbps) {
    return 'Lista · $kbps kbps';
  }

  @override
  String broadcastBitrate(String mbps) {
    return '$mbps Mbps';
  }

  @override
  String get broadcastStart => 'Emitir';

  @override
  String get broadcastStop => 'Detener';

  @override
  String get broadcastStopTitle => '¿Detener la emisión?';

  @override
  String get broadcastStopBody =>
      'La emisión en YouTube termina para todos los que la estén viendo.';

  @override
  String get broadcastStopKeep => 'Seguir emitiendo';

  @override
  String get broadcastSettings => 'Ajustes de emisión';

  @override
  String get broadcastServer => 'Servidor';

  @override
  String get broadcastKey => 'Clave de emisión';

  @override
  String broadcastKeyKeep(String hint) {
    return 'Déjala vacía para mantener •••• $hint';
  }

  @override
  String get broadcastKeyHelp =>
      'En YouTube Studio: Crear > Emitir en directo > Clave de emisión.';

  @override
  String get broadcastKeyShow => 'Mostrar la clave';

  @override
  String get broadcastKeyHide => 'Ocultar la clave';

  @override
  String get broadcastPaste => 'Pegar';

  @override
  String broadcastBitrateLabel(int kbps) {
    return 'Bitrate de vídeo: $kbps kbps';
  }

  @override
  String get broadcastAudio => 'Sonido del micrófono';

  @override
  String get broadcastCancel => 'Cancelar';

  @override
  String get broadcastSave => 'Guardar';

  @override
  String broadcastFailed(String message) {
    return 'No se pudo emitir: $message';
  }

  @override
  String get broadcastMicDenied =>
      'Micrófono no permitido: se emite sin sonido';

  @override
  String get broadcastNotBroadcastMode => 'La cámara no está en modo emisión';

  @override
  String get scoreboardTitle => 'Marcador';

  @override
  String scoreboardHalf(int period) {
    return '${period}T';
  }

  @override
  String scoreboardPlus(String team) {
    return 'Sumar un punto a $team';
  }

  @override
  String scoreboardMinus(String team) {
    return 'Quitar un punto a $team';
  }

  @override
  String get scoreboardStartClock => 'Poner el reloj en marcha';

  @override
  String get scoreboardPauseClock => 'Parar el reloj';

  @override
  String get scoreboardSetClock => 'Ajustar el reloj';

  @override
  String get scoreboardHoldToSetClock =>
      'Mantén pulsado el reloj para ajustarlo';

  @override
  String get scoreboardMinutes => 'Minutos';

  @override
  String get scoreboardSeconds => 'Segundos';

  @override
  String get scoreboardMore => 'Periodo, mostrar y ajustes';

  @override
  String get scoreboardHidden => 'Marcador oculto';

  @override
  String scoreboardGoToPeriod(String period) {
    return 'Pasar a $period';
  }

  @override
  String scoreboardBackToPeriod(String period) {
    return 'Volver a $period';
  }

  @override
  String scoreboardPeriodConfirmTitle(String period) {
    return '¿Pasar a $period?';
  }

  @override
  String scoreboardPeriodConfirmBody(String time) {
    return 'El reloj se para y se pone a $time.';
  }

  @override
  String get scoreboardPeriodConfirm => 'Cambiar de periodo';

  @override
  String get scoreboardSize => 'Tamaño del marcador';

  @override
  String get scoreboardSizeSmall => 'Pequeño';

  @override
  String get scoreboardSizeMedium => 'Mediano';

  @override
  String get scoreboardSizeLarge => 'Grande';

  @override
  String get panelsTitle => 'Paneles';

  @override
  String get panelLive => 'Directo';

  @override
  String get panelScoreboard => 'Marcador';

  @override
  String get panelReplays => 'Repeticiones';

  @override
  String get panelsNothingShown =>
      'Está todo oculto. Usa el botón de paneles de arriba para mostrar el directo, el marcador o las repeticiones.';

  @override
  String get cameraScoreboardControls => 'Controles del marcador';

  @override
  String get cameraConnectViewer => 'Conectar un visor';

  @override
  String get zoomOut => 'Alejar';

  @override
  String get zoomIn => 'Acercar';

  @override
  String get zoomReset => 'Volver a 1×';

  @override
  String get switchRoleTitle => '¿Cambiar de rol?';

  @override
  String get switchRoleBroadcastBody =>
      'La cámara está emitiendo. Cambiar de rol corta la emisión en YouTube y desconecta a todos los visores.';

  @override
  String get switchRoleViewerBody =>
      'Estás conectado a la cámara. Cambiar de rol cierra el directo y esta conexión.';

  @override
  String switchRoleViewersBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hay $count visores conectados. Cambiar de rol para la cámara y los desconecta.',
      one:
          'Hay un visor conectado. Cambiar de rol para la cámara y lo desconecta.',
    );
    return '$_temp0';
  }

  @override
  String get clipReserveTitle => 'Reserva de repeticiones';

  @override
  String get clipReserveOff =>
      'Desactivada: la cámara borra cada clip en cuanto está en la tablet.';

  @override
  String clipReserveHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'La cámara guarda los últimos $count clips para poder emitirlos.',
      one: 'La cámara guarda el último clip para poder emitirlo.',
    );
    return '$_temp0';
  }

  @override
  String get clipReserveLess => 'Menos';

  @override
  String get clipReserveMore => 'Más';

  @override
  String get clipReserveDone => 'Hecho';

  @override
  String get clipOnCamera => 'En la cámara';

  @override
  String get broadcastReplayScoreboard => 'Marcador en las repeticiones';

  @override
  String get broadcastReplayScoreboardHint =>
      'Desactivado: la repetición en antena solo muestra el cartel REPETICIÓN.';

  @override
  String get roleBroadcast => 'Retransmisión';

  @override
  String get roleBroadcastEntry => 'Retransmitir partido · beta';

  @override
  String get roleBroadcastDescription =>
      'Emite en YouTube con marcador y repeticiones.';

  @override
  String get checkTitle => 'Antes de emitir';

  @override
  String get checkKeyOk => 'Emite con la clave de emisión guardada';

  @override
  String get checkKeyMissing => 'Falta la clave de emisión de YouTube';

  @override
  String get checkKeyAction => 'Añadir';

  @override
  String get checkQualityUnknown => 'Calidad: la cámara está arrancando';

  @override
  String checkQualityOk(String profile) {
    return 'Calidad $profile';
  }

  @override
  String checkQualityLow(String profile) {
    return 'Calidad $profile: en YouTube se ve mejor a 1080p';
  }

  @override
  String get checkQualityAction => 'Usar 1080p';

  @override
  String get checkInternetOk => 'Hay Internet';

  @override
  String get checkInternetMissing =>
      'Sin Internet: usa una Wi-Fi con Internet o comparte datos móviles';

  @override
  String get checkInternetChecking => 'Comprobando Internet…';

  @override
  String get checkPowerOk => 'Cargando';

  @override
  String get checkPowerMissing =>
      'No está cargando: enchúfalo para un partido entero';

  @override
  String get checkMicOk => 'Micrófono permitido';

  @override
  String get checkMicMissing =>
      'Micrófono sin permiso: la emisión irá sin sonido';

  @override
  String get checkMicAction => 'Permitir';

  @override
  String get broadcastMicMute => 'Silenciar el micrófono en la emisión';

  @override
  String get broadcastMicUnmute => 'Activar el micrófono en la emisión';

  @override
  String get broadcastMicNextStream =>
      'Aún sin permiso de micrófono: sonará a partir de la próxima emisión';

  @override
  String get scoreboardSet => 'Ajustar';

  @override
  String get scoreboardVisible => 'En pantalla';

  @override
  String get scoreboardReset => 'Reiniciar';

  @override
  String get scoreboardResetTitle => '¿Reiniciar el marcador?';

  @override
  String get scoreboardResetBody =>
      'Marcador a 0, primer periodo y reloj a cero. Los nombres y los ajustes se mantienen.';

  @override
  String get scoreboardSettings => 'Ajustes del marcador';

  @override
  String get scoreboardHome => 'Local';

  @override
  String get scoreboardAway => 'Visitante';

  @override
  String get scoreboardTeamName => 'Nombre (hasta 5 letras)';

  @override
  String scoreboardTeamColor(String team) {
    return 'Color de $team';
  }

  @override
  String get scoreboardPeriods => 'Periodos';

  @override
  String get scoreboardPeriodMinutes => 'Minutos por periodo';

  @override
  String get scoreboardClockDirection => 'Reloj';

  @override
  String get scoreboardCountUp => 'Ascendente';

  @override
  String get scoreboardCountDown => 'Descendente';

  @override
  String get replayLabelOnAir => 'REPETICIÓN';

  @override
  String get replayOnAir => 'REPETICIÓN EN ANTENA';

  @override
  String get replayBackToLive => 'Volver al directo';

  @override
  String get replaySpeed => 'Velocidad de la repetición';

  @override
  String get replayChoiceTitle => '¿Dónde ver la jugada?';

  @override
  String get replayChoiceTablet => 'Solo en la tablet';

  @override
  String get replayChoiceAir => 'También en emisión';

  @override
  String get replayNotLive => 'La emisión no está en marcha';

  @override
  String get replayUnavailable => 'Este clip ya no está en la cámara';

  @override
  String replayFailed(String message) {
    return 'No se pudo emitir la repetición: $message';
  }

  @override
  String get broadcastModeKey => 'Clave';

  @override
  String get broadcastModeAccount => 'Cuenta de YouTube';

  @override
  String get youtubeAccountHelp =>
      'Inicia sesión con la cuenta de Google del canal: la app crea el directo (título y visibilidad), envía la clave a la cámara y el directo empieza y termina solo con la emisión.';

  @override
  String get youtubeSignIn => 'Iniciar sesión con Google';

  @override
  String get youtubeSignOut => 'Cerrar sesión';

  @override
  String get youtubeWillCreate =>
      'Al guardar se crea un directo nuevo en el canal.';

  @override
  String get youtubeTitle => 'Título';

  @override
  String get youtubeDescription => 'Descripción';

  @override
  String get youtubePrivacy => 'Visibilidad';

  @override
  String get youtubePrivacyPublic => 'Público';

  @override
  String get youtubePrivacyUnlisted => 'Oculto';

  @override
  String get youtubePrivacyPrivate => 'Privado';

  @override
  String youtubeDefaultTitle(String date) {
    return 'Partido $date';
  }

  @override
  String get youtubeLifeReady => 'Preparado: empieza en cuanto llegue la señal';

  @override
  String get youtubeLifeStarting => 'YouTube está arrancando el directo';

  @override
  String get youtubeLifeLive => 'En directo en YouTube';

  @override
  String get youtubeLifeComplete => 'Terminado: al guardar se crea uno nuevo';

  @override
  String get youtubeIngestGood => 'YouTube está recibiendo la señal';

  @override
  String get youtubeIngestBad => 'YouTube recibe la señal con problemas';

  @override
  String get youtubeIngestNone => 'YouTube no está recibiendo nada';

  @override
  String get youtubeCopyLink => 'Copiar enlace';

  @override
  String get youtubeLinkCopied => 'Enlace copiado';

  @override
  String get youtubeRefresh => 'Actualizar';

  @override
  String get youtubeNewLive => 'Nuevo directo';

  @override
  String get youtubeErrorLiveNotEnabled =>
      'Este canal todavía no puede emitir en directo. Actívalo en YouTube Studio > Emitir en directo (puede tardar 24 h).';

  @override
  String get youtubeErrorQuota =>
      'Se ha agotado la cuota diaria de la API de YouTube. De momento usa una clave de emisión.';

  @override
  String get youtubeErrorForbidden =>
      'YouTube ha denegado el acceso. Vuelve a iniciar sesión.';

  @override
  String get youtubeErrorNetwork =>
      'No se puede conectar con YouTube. Revisa la conexión a internet.';

  @override
  String youtubeErrorSignIn(String message) {
    return 'No se pudo iniciar sesión: $message';
  }

  @override
  String youtubeErrorApi(String message) {
    return 'Error de YouTube: $message';
  }

  @override
  String get youtubeQr => 'QR';

  @override
  String get youtubeQrTitle => 'Ver el directo';

  @override
  String get youtubeQrClose => 'Cerrar';

  @override
  String get youtubeNeedSignIn =>
      'La emisión va a tu cuenta de YouTube: vuelve a iniciar sesión en los ajustes de emisión o cambia a Clave.';

  @override
  String get youtubeShare => 'Compartir';

  @override
  String get reviewDraw => 'Dibujar';

  @override
  String get reviewDrawActive => 'Pizarra activa';

  @override
  String get reviewChangeTag => 'Cambiar etiqueta';

  @override
  String get reviewExport => 'Exportar';

  @override
  String get reviewMore => 'Más';

  @override
  String get reviewAirSend => 'Emitir repetición';

  @override
  String get reviewAirStop => 'Quitar de antena';

  @override
  String get reviewOnAirBanner => 'EN ANTENA · LO VE YOUTUBE';

  @override
  String reviewClipOf(int index, int count) {
    return 'clip $index de $count';
  }

  @override
  String reviewFrameCounter(int frame, int total) {
    return 'F $frame / $total';
  }

  @override
  String get reviewFrameBack => '−1 fot.';

  @override
  String get reviewFrameForward => '+1 fot.';

  @override
  String get reviewLoading => 'Cargando el clip…';

  @override
  String get reviewRetry => 'Reintentar';

  @override
  String get reviewToolArrow => 'Flecha';

  @override
  String get reviewToolCircle => 'Círculo';

  @override
  String get reviewToolLine => 'Línea';

  @override
  String get reviewToolPen => 'Lápiz';

  @override
  String get reviewToolEraser => 'Goma';

  @override
  String get reviewToolSelect => 'Mover';

  @override
  String get reviewThick => 'Gruesa';

  @override
  String get reviewUndo => 'Deshacer';

  @override
  String get reviewClearAll => 'Borrar todo';

  @override
  String get reviewDeleteMark => 'Borrar';

  @override
  String get reviewDone => 'Hecho';

  @override
  String get connectStepCamera => 'Cámara';

  @override
  String get connectStepCode => 'Código';

  @override
  String get connectStepSession => 'Sesión';

  @override
  String get connectScanSubtitle => 'Lo muestra la pantalla de la cámara';

  @override
  String get connectManual => 'Escribir la dirección a mano';

  @override
  String get connectCodeHint =>
      'Son los 6 números grandes bajo el QR de la cámara';

  @override
  String get connectOtherCamera => 'Elegir otra cámara';

  @override
  String connectPickerConnectedTo(String name) {
    return 'Conectado a $name';
  }

  @override
  String get connectPickerQuestion => '¿Qué vas a grabar?';

  @override
  String get connectPickerContinue => 'Continuar esta sesión';

  @override
  String get connectPickerNewMatch => 'Nuevo partido';

  @override
  String get connectPickerNewTraining => 'Nuevo entreno';

  @override
  String get connectPickerNewOther => 'Otra sesión';

  @override
  String get connectPickerNameHint => 'Vacío: tipo y fecha';

  @override
  String get libFilterAll => 'Todo';

  @override
  String get libFilterMatches => 'Partidos';

  @override
  String get libFilterTrainings => 'Entrenos';

  @override
  String get libSelect => 'Seleccionar';

  @override
  String get libSelectCancel => 'Cancelar';

  @override
  String libExportCount(int count) {
    return 'Exportar $count';
  }

  @override
  String get libShare => 'Compartir';

  @override
  String get libEmptyHint => 'Los clips que guardes en directo aparecen aquí.';

  @override
  String get libFilterEmpty => 'Nada con este filtro.';

  @override
  String get libError => 'No se pudo abrir la biblioteca';

  @override
  String get libRetry => 'Reintentar';

  @override
  String get libTemplatesBuiltIn => 'Incluidas';

  @override
  String get libTemplatesImported => 'Importadas';

  @override
  String get liveSaveTitle => 'Guardar jugada';

  @override
  String liveSaveSubtitle(int seconds, int post) {
    return 'los últimos $seconds s y $post s más';
  }

  @override
  String get liveOnAirBadge => 'EN VIVO';

  @override
  String get liveNoSoundBadge => 'EMISIÓN SIN SONIDO';

  @override
  String get liveMicOpen => 'Micro abierto';

  @override
  String get liveMicClosed => 'Micro cerrado';

  @override
  String get liveMenu => 'Menú';

  @override
  String get liveRestart => 'Reiniciar';

  @override
  String get liveClipsEmptyHint =>
      'Toca Guardar jugada justo después de la jugada.';

  @override
  String get liveTagPanelTitle => 'Guardado · ¿qué ha sido?';

  @override
  String get livePlayClip => 'Ver';

  @override
  String liveTeams(String home, String away) {
    return '$home vs $away';
  }

  @override
  String get liveGlanceTitle => 'Partido de un vistazo';

  @override
  String get liveGlanceHint => 'Toca una marca para revisarla';

  @override
  String get camWhatYouTubeSees => 'Lo que ve YouTube';

  @override
  String get camNoSound => 'SIN SONIDO';

  @override
  String get camStreamTitle => 'Emisión';

  @override
  String get camOnAirYouTube => 'En directo en YouTube';

  @override
  String get camOnAirFor => 'en el aire';

  @override
  String get camMbps => 'Mbps';

  @override
  String get camViewersLabel => 'visores';

  @override
  String get camStopStream => 'Parar emisión';

  @override
  String get camStopShort => 'Parar';

  @override
  String get camMicOpen => 'Micro abierto';

  @override
  String get camMicOpenHint => 'Toca para cerrarlo';

  @override
  String get camMicClosed => 'Micro cerrado';

  @override
  String get camMicClosedHint => 'YouTube no oye nada · toca para abrirlo';

  @override
  String get camTileTemperature => 'Temperatura';

  @override
  String get camTileMemory => 'Memoria';

  @override
  String get camTileViewers => 'Visores';

  @override
  String get camTileOutbox => 'Por enviar';

  @override
  String get camTileCharging => 'Cargando';

  @override
  String camConnectViewerSub(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conectados',
      one: '1 conectado',
      zero: 'nadie conectado',
    );
    return 'QR y código · $_temp0';
  }

  @override
  String get camPairSheetSub =>
      'Escanéalo desde InstantReplay en la tablet o el móvil del banquillo';

  @override
  String get camPairOrCode => 'O escribe este código en el visor';

  @override
  String get camConnectedNow => 'Conectados ahora';

  @override
  String get camClose => 'Cerrar';

  @override
  String get camShareLive => 'Compartir el directo';

  @override
  String get camShareLiveSub => 'Enlace de YouTube para familias';

  @override
  String get camShareSheetSub =>
      'Que lo escaneen con la cámara del móvil: abre el directo en YouTube';

  @override
  String get camShareHint =>
      '«Compartir…» abre WhatsApp, correo y el resto de apps del móvil.';

  @override
  String get camShareAction => 'Compartir…';

  @override
  String get camPrivacyChangeHint => 'Cámbialo en Preparar la emisión.';

  @override
  String get camPrepareStream => 'Preparar la emisión';

  @override
  String get camBlackScreen => 'Pantalla negra';

  @override
  String get camScoreboardShort => 'Ajustes marcador';

  @override
  String get camReadyTitle => 'Todo listo para emitir';

  @override
  String get camReadySub => 'Todo comprobado. Emite cuando quieras.';

  @override
  String get camAmberHint => 'Los avisos en ámbar no impiden emitir.';

  @override
  String get camOperatingTitle =>
      'Grabando · pantalla apagada para ahorrar batería';

  @override
  String get camSavedForNext => 'Se guarda para el próximo partido';

  @override
  String get camTabDestination => 'Destino';

  @override
  String get camTabDestinationSub => 'YouTube · cuenta o clave';

  @override
  String get camTabImage => 'Imagen y sonido';

  @override
  String get camTabImageSub => 'Calidad y micrófono';

  @override
  String get camTabReplays => 'Repeticiones';

  @override
  String get camTabReplaysSub => 'Cómo salen en antena';

  @override
  String get camStepImage => 'Imagen';

  @override
  String get camStepCheck => 'Comprobar';

  @override
  String get camWhereStream => '¿Dónde se emite?';

  @override
  String get camQualityTitle => 'Calidad de la imagen';

  @override
  String get camQualityLow => 'Ahorro';

  @override
  String get camQualityNormal => 'Normal';

  @override
  String get camQualityHigh => 'Alta';

  @override
  String get camQualityLowSub => 'datos móviles';

  @override
  String get camQualityNormalSub => 'recomendado';

  @override
  String get camQualityHighSub => 'wifi buena';

  @override
  String camQualityPerHour(String gigabytes) {
    return '≈ $gigabytes GB por hora';
  }

  @override
  String get camQualityAuto =>
      'Si la conexión baja, la emisión reduce la calidad sola para no cortarse.';

  @override
  String get camFineTune => 'Ajuste fino';

  @override
  String get camSoundTitle => 'Sonido';

  @override
  String get camMicTitle => 'Micrófono de la cámara';

  @override
  String get camMicSub =>
      'Ambiente del pabellón. Se puede silenciar en directo.';

  @override
  String get camReplaysTitle => 'Cómo salen las repeticiones';

  @override
  String get camGoLiveNow => 'Empezar a emitir';

  @override
  String get camGoLiveLast => 'Emitir ya, como la última vez';

  @override
  String get camNext => 'Siguiente';

  @override
  String get camSummary => 'RESUMEN';

  @override
  String get camSumKey => 'Clave';

  @override
  String camSumYouTube(String privacy) {
    return 'YouTube · $privacy';
  }

  @override
  String get camSumReplay => 'Repetición';

  @override
  String get camSumScoreboardOn => 'con marcador';

  @override
  String get camSumScoreboardOff => 'solo el cartel';

  @override
  String get camYes => 'Sí';

  @override
  String get camNo => 'No';

  @override
  String get camWhoCanSee => 'Quién puede verlo';

  @override
  String get camPrivacyPublicSub => 'Cualquiera la encuentra';

  @override
  String get camPrivacyUnlistedSub => 'Solo con el enlace';

  @override
  String get camPrivacyPrivateSub => 'Solo tu cuenta';

  @override
  String get camBack => 'Volver';

  @override
  String get sbPageTitle => 'Marcador de la emisión';

  @override
  String get sbStyle => 'Estilo';

  @override
  String get sbClassic => 'Clásico';

  @override
  String get sbClassicSub => 'Una barra fina. Nombres de hasta 5 letras.';

  @override
  String get sbPlate => 'Placa';

  @override
  String get sbPlateSub => 'Dos filas. Nombres completos de hasta 16 letras.';

  @override
  String get sbDefault => 'POR DEFECTO';

  @override
  String get sbClassicCut =>
      'El estilo Clásico corta los nombres a 5 letras. En Placa se ven completos.';

  @override
  String get sbPreview => 'VISTA PREVIA';

  @override
  String get sbHomeTeam => 'Equipo local';

  @override
  String get sbAwayTeam => 'Equipo visitante';

  @override
  String get sbTeamName => 'Nombre';

  @override
  String get sbSizeOnScreen => 'Tamaño en pantalla';

  @override
  String get sbMatch => 'Partido';

  @override
  String get sbReplayBadge => 'REPETICIÓN';

  @override
  String get sbClockStart => 'Arrancar reloj';

  @override
  String get sbClockPause => 'Pausar reloj';

  @override
  String get camShareLoading => 'Preparando el enlace de YouTube…';

  @override
  String get camShareLoadingSub =>
      'La primera vez tarda unos segundos; luego se abre al momento.';

  @override
  String get camShareRetry => 'Reintentar';

  @override
  String get sbVisibility => 'Qué se ve';

  @override
  String get sbOnAir => 'Marcador en la emisión';

  @override
  String get sbOnAirSub => 'Apágalo para emitir sin marcador';

  @override
  String get sbControls => 'Controles del marcador en esta pantalla';

  @override
  String get sbControlsSub => 'Ocúltalos si otra persona lleva el marcador';

  @override
  String get sbChangeColour => 'Cambiar color';

  @override
  String get camInfoTitle => 'Estado de la cámara';

  @override
  String get camRecordingTitle => 'Grabación de la cámara';

  @override
  String get camSameWifi =>
      'Los visores tienen que estar en la misma red Wi-Fi que esta cámara, o conectados a su punto de acceso.';

  @override
  String get connectSameWifi =>
      'Este dispositivo y la cámara tienen que estar en la misma red Wi-Fi (o este, en el punto de acceso de la cámara).';

  @override
  String get settingsAppTitle => 'Ajustes de la app';

  @override
  String get viewerThisScreen => 'Esta pantalla';

  @override
  String get viewerSaveButtons => 'Botones de Guardar';

  @override
  String checkAccountOk(String email) {
    return 'Emite en la cuenta de YouTube $email';
  }

  @override
  String get checkAccountSignIn =>
      'Inicia sesión en la cuenta de YouTube para emitir';

  @override
  String get liveMicClosedBadge => 'MICRO CERRADO';

  @override
  String ytAccountCheckChannel(String channel) {
    return 'Emite en el canal $channel';
  }

  @override
  String get ytAccountKeyLocked =>
      'Estás usando tu cuenta de YouTube. Cierra sesión para emitir con una clave.';

  @override
  String get ytAccountOrUseKey =>
      'O cierra sesión y emite con una clave de emisión.';

  @override
  String get ytAccountErrorQuota =>
      'Se ha agotado la cuota diaria de la API de YouTube.';

  @override
  String get reviewColourRed => 'rojo';

  @override
  String get reviewColourYellow => 'amarillo';

  @override
  String get reviewColourWhite => 'blanco';

  @override
  String get reviewColourBlue => 'azul';

  @override
  String get reviewColourBlack => 'negro';

  @override
  String get liveOnYouTubeBadge => 'EN ANTENA';

  @override
  String get ytRemoteOrUseKey =>
      'O cierra sesión en la cámara y emite con una clave de emisión.';

  @override
  String get ytRemoteNeedSignIn =>
      'La emisión va a la cuenta de YouTube de la cámara: vuelve a iniciar sesión en la cámara, o cambia a Clave.';

  @override
  String get ytRemoteNoCamera =>
      'La cámara no ha respondido. Revisa la conexión e inténtalo de nuevo.';

  @override
  String get ytRemoteUnavailable =>
      'Esta cámara no puede usar una cuenta de YouTube. Usa una clave de emisión.';

  @override
  String get ytRemoteKeyLocked =>
      'La cámara usa su cuenta de YouTube. Para emitir con una clave, cierra sesión en la cámara.';

  @override
  String get ytRemoteSignInHelp =>
      'La cuenta de YouTube se configura en la cámara: inicia sesión con Google allí, una vez. Mientras tanto puedes emitir con una clave.';

  @override
  String get ytRemoteOnCamera => 'Sesión iniciada en la cámara';

  @override
  String get ytDestKey => 'Emite con clave manual';
}
