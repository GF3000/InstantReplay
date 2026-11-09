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
  String get cameraStarting => 'Starting the camera…';

  @override
  String get cameraPermissionDenied =>
      'InstantReplay needs camera permission to record.';

  @override
  String get cameraNoProfiles =>
      'This device has no supported recording quality.';

  @override
  String cameraStartFailed(String error) {
    return 'The camera could not start: $error';
  }

  @override
  String get cameraRetry => 'Try again';

  @override
  String get cameraProfile => 'Quality';

  @override
  String get cameraStartOperating => 'Start operating';

  @override
  String get cameraOperatingHint => 'Tap anywhere to return to setup';

  @override
  String cameraOperatingStatus(int seconds, int clips, String temperature) {
    return 'REC · buffer $seconds s · outbox $clips · $temperature';
  }

  @override
  String get cameraWaitingForStats => 'Waiting for statistics…';

  @override
  String get cameraStatCamera => 'Camera';

  @override
  String get cameraStatFps => 'Frame rate';

  @override
  String cameraFpsValue(String fps) {
    return '$fps fps';
  }

  @override
  String get cameraStatGaps => 'Frame gaps';

  @override
  String cameraGapsValue(int total, int camera, int gl) {
    return '$total (camera $camera, GL $gl)';
  }

  @override
  String get cameraStatBuffer => 'Buffer';

  @override
  String cameraBufferValue(int seconds, String megabytes) {
    return '$seconds s · $megabytes MB';
  }

  @override
  String get cameraStatOutbox => 'Outbox';

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
  String get cameraStatThermal => 'Thermal status';

  @override
  String get cameraStatBattery => 'Battery';

  @override
  String cameraBatteryValue(String temperature, String percent, String power) {
    return '$temperature · $percent · $power';
  }

  @override
  String get cameraCharging => 'charging';

  @override
  String get cameraNotCharging => 'not charging';

  @override
  String get cameraNotChargingWarning =>
      'Not charging. Connect power for long sessions.';

  @override
  String get cameraNotificationsDenied =>
      'Notifications are off, so Android will not show the recording notice. Recording still works.';

  @override
  String get cameraErrorsTitle => 'Camera errors';

  @override
  String get cameraDismissErrors => 'Dismiss';

  @override
  String get cameraSaveTestClip => 'Save test clip (last 20 s)';

  @override
  String cameraTestClipSaved(String seconds, String megabytes) {
    return 'Test clip saved: $seconds s, $megabytes MB';
  }

  @override
  String cameraTestClipFailed(String error) {
    return 'Test clip failed: $error';
  }

  @override
  String get thermalNone => 'Normal';

  @override
  String get thermalLight => 'Light';

  @override
  String get thermalModerate => 'Moderate';

  @override
  String get thermalSevere => 'Severe';

  @override
  String get thermalCritical => 'Critical';

  @override
  String get thermalEmergency => 'Emergency';

  @override
  String get thermalShutdown => 'Shutdown';

  @override
  String get viewerConnectTitle => 'Connect to the camera';

  @override
  String get viewerAddressLabel => 'Camera address';

  @override
  String get viewerAddressInvalid =>
      'Enter an address like http://192.168.1.20:8080';

  @override
  String get viewerAddressSubmit => 'Continue';

  @override
  String get viewerScanQr => 'Scan QR';

  @override
  String get viewerScanHint => 'Point at the QR shown on the camera';

  @override
  String get viewerScanNotCamera =>
      'This QR is not from an InstantReplay camera. Keep pointing at the camera\'s QR.';

  @override
  String get viewerScanPermissionDenied =>
      'No camera permission. Type the address, or allow the camera in Settings.';

  @override
  String get viewerCodeTitle => 'Enter the code shown on the camera';

  @override
  String viewerCameraAt(String address) {
    return 'Camera at $address';
  }

  @override
  String get viewerCodeLabel => '6-digit code';

  @override
  String get viewerCodeSubmit => 'Connect';

  @override
  String get viewerCodeWrong =>
      'Wrong code. Check the camera screen and try again.';

  @override
  String get viewerCodeTooManyAttempts =>
      'Too many attempts. Wait a minute and try again.';

  @override
  String get viewerCameraUnreachable =>
      'Cannot reach the camera. Check that both devices are on the same Wi-Fi.';

  @override
  String get viewerSessionExpired =>
      'The camera started a new session. Enter its new code.';

  @override
  String get viewerChangeCamera => 'Change camera';

  @override
  String get viewerLinkConnecting => 'Connecting…';

  @override
  String get viewerLinkReconnecting => 'Reconnecting…';

  @override
  String get viewerLinkIncompatible =>
      'This camera runs another version of InstantReplay. Update both devices.';

  @override
  String get viewerLiveStarting => 'Starting live view…';

  @override
  String get viewerLiveInterrupted => 'Live view interrupted. Restarting…';

  @override
  String get viewerLiveRestart => 'Restart live view';

  @override
  String get viewerStatusRec => 'REC';

  @override
  String get viewerStatusIdle => 'Not recording';

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
    return 'SAVE $seconds s';
  }

  @override
  String viewerSaveQuick(int seconds) {
    return '$seconds s';
  }

  @override
  String viewerSaveHint(int seconds) {
    return 'Saves the last seconds plus $seconds s after the tap.';
  }

  @override
  String get viewerSessionOnlyNotice =>
      'Clips stay in this browser tab only. Download the ones you want to keep.';

  @override
  String get viewerClipsEmpty => 'Saved clips appear here.';

  @override
  String get viewerClipRequesting => 'Requesting…';

  @override
  String get viewerClipRecording => 'Recording…';

  @override
  String get viewerClipDownloadingStarted => 'Downloading…';

  @override
  String viewerClipDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get viewerClipReady => 'Ready';

  @override
  String get viewerClipFailedRequest => 'The camera did not answer';

  @override
  String get viewerClipFailedDownload => 'Download failed';

  @override
  String get viewerClipFailedChecksum => 'The download was corrupted';

  @override
  String get viewerClipExpired => 'Expired on the camera';

  @override
  String get viewerClipRetry => 'Retry';

  @override
  String get viewerClipDownload => 'Download';

  @override
  String get viewerReviewPrevFrame => 'Previous frame';

  @override
  String get viewerReviewZoomReset => 'Reset zoom';

  @override
  String get viewerReviewNextFrame => 'Next frame';

  @override
  String get viewerDraw => 'Draw';

  @override
  String get viewerDrawColor => 'Colour';

  @override
  String get viewerDrawUndo => 'Undo';

  @override
  String get viewerDrawClear => 'Clear drawing';

  @override
  String get viewerDrawDone => 'Done';

  @override
  String get viewerDrawArrow => 'Arrow';

  @override
  String get viewerDrawCircle => 'Circle';

  @override
  String get viewerDrawLine => 'Straight line';

  @override
  String get viewerDrawPen => 'Freehand';

  @override
  String get viewerDrawSelect => 'Select and move';

  @override
  String get viewerDrawEraser => 'Eraser';

  @override
  String get viewerDrawDelete => 'Delete mark';

  @override
  String get viewerDrawThick => 'Thick line';

  @override
  String get viewerReviewPrevClip => 'Previous clip';

  @override
  String get viewerReviewNextClip => 'Next clip';

  @override
  String get viewerReviewPlaylistRestart => 'Watch all again';

  @override
  String viewerReviewPlaylistPosition(int index, int count) {
    return '$index / $count';
  }

  @override
  String get viewerReviewPlay => 'Play';

  @override
  String get viewerReviewPause => 'Pause';

  @override
  String viewerReviewSpeed(double speed) {
    final intl.NumberFormat speedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String speedString = speedNumberFormat.format(speed);

    return '$speedString×';
  }

  @override
  String get viewerReviewError => 'This clip cannot be played here.';

  @override
  String get cameraPairingTitle => 'Connect a viewer';

  @override
  String get cameraPairingCode => 'Pairing code';

  @override
  String get cameraPairingScanHint =>
      'Scan the QR code, or open this address in a browser on the same Wi-Fi:';

  @override
  String get cameraPairingNoNetwork =>
      'No Wi-Fi or hotspot found. Turn on the hotspot or join a Wi-Fi network.';

  @override
  String cameraViewersConnected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viewers connected',
      one: '1 viewer connected',
      zero: 'No viewers connected',
    );
    return '$_temp0';
  }

  @override
  String cameraOperatingViewers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viewers',
      one: '1 viewer',
    );
    return '$_temp0';
  }

  @override
  String get serverStarting => 'Starting the viewer server…';

  @override
  String serverStartFailed(String error) {
    return 'The viewer server could not start: $error';
  }

  @override
  String get viewerStatusTitle => 'Camera status';

  @override
  String get viewerStatusRecording => 'Recording';

  @override
  String get viewerStatusFpsLabel => 'Frame rate';

  @override
  String get viewerStatusBufferLabel => 'Replay buffer';

  @override
  String viewerStatusSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get viewerStatusPendingLabel => 'Clips pending on the camera';

  @override
  String get viewerStatusTemperatureLabel => 'Temperature';

  @override
  String get viewerStatusBatteryLabel => 'Battery';

  @override
  String viewerStatusBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get viewerStatusCharging => 'charging';

  @override
  String get viewerStatusNotCharging => 'not charging';

  @override
  String get viewerProblemDisconnected => 'Disconnected';

  @override
  String get viewerProblemHot => 'Overheating';

  @override
  String viewerProblemBatteryLow(int percent) {
    return 'Battery $percent%';
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
  String get viewerClipChangeTag => 'Tag';

  @override
  String get viewerClipNoTag => 'No tag';

  @override
  String get viewerFilterAll => 'All';

  @override
  String get viewerTagDefaultGood => 'Good';

  @override
  String get viewerTagDefaultBad => 'Bad';

  @override
  String get viewerTagDefaultOther => 'Other';

  @override
  String get viewerTagsEdit => 'Edit tags';

  @override
  String get viewerTagsTitle => 'Tags';

  @override
  String get viewerTagsAdd => 'Add tag';

  @override
  String get viewerTagsEmpty => 'No tags. Add one to label your clips.';

  @override
  String get viewerTagEdit => 'Edit tag';

  @override
  String get viewerTagName => 'Name';

  @override
  String get viewerTagColor => 'Colour';

  @override
  String get viewerTagDelete => 'Delete tag';

  @override
  String get viewerTagCancel => 'Cancel';

  @override
  String get viewerTagOk => 'Save';

  @override
  String get cameraAdvanced => 'Advanced';

  @override
  String cameraHotWarning(String level) {
    return 'The phone is hot ($level). Shade it or lower the quality.';
  }

  @override
  String viewerTagDeleted(String name) {
    return '\"$name\" deleted';
  }

  @override
  String get viewerTagUndo => 'Undo';

  @override
  String get recTitle => 'Full recording';

  @override
  String get recRecord => 'Record';

  @override
  String get recResume => 'Resume';

  @override
  String get recPause => 'Pause';

  @override
  String get recFinish => 'Finish';

  @override
  String get recOptions => 'Recording options';

  @override
  String get recFromNow => 'Record from now';

  @override
  String get recResumeFromNow => 'Resume from now';

  @override
  String recIncludeLast(int seconds) {
    return 'Record including the last $seconds s';
  }

  @override
  String recResumeIncludeLast(int seconds) {
    return 'Resume including the last $seconds s';
  }

  @override
  String get recIdle => 'Not recording';

  @override
  String recPaused(String elapsed) {
    return 'Paused · $elapsed';
  }

  @override
  String recPart(int part) {
    return 'part $part';
  }

  @override
  String recRemaining(String time) {
    return '$time left';
  }

  @override
  String recLowSpace(String time) {
    return 'Low space: $time left';
  }

  @override
  String get recLowSpaceUnknown => 'Low space on the camera';

  @override
  String recFree(String gigabytes) {
    return '$gigabytes GB free';
  }

  @override
  String get recFinishTitle => 'Finish the recording?';

  @override
  String recFinishBody(String elapsed) {
    return 'The $elapsed recorded will be saved to the camera\'s gallery (Movies/InstantReplay).';
  }

  @override
  String get recFinishKeep => 'Keep recording';

  @override
  String recSaved(int parts, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      parts,
      locale: localeName,
      other:
          'Recording saved to the camera\'s gallery ($duration, $parts parts)',
      one: 'Recording saved to the camera\'s gallery ($duration)',
    );
    return '$_temp0';
  }

  @override
  String recSavedLowSpace(String duration) {
    return 'The camera ran out of space: the recording stopped and was saved ($duration)';
  }

  @override
  String recSavedError(String duration) {
    return 'The recording stopped because of an error; what was recorded is saved ($duration)';
  }

  @override
  String recRecovered(String duration) {
    return 'Recovered a $duration recording';
  }

  @override
  String get recRecoveredHint =>
      'It was left open when the app closed. It is in the gallery (Movies/InstantReplay).';

  @override
  String get recNoSpace =>
      'Not enough space on the camera to record (it needs 1 GB free)';

  @override
  String recFailed(String message) {
    return 'Recording failed: $message';
  }

  @override
  String get viewerClipSaveToGallery => 'Save to gallery';

  @override
  String get viewerClipShare => 'Share';

  @override
  String get viewerClipSavedToGallery => 'Saved to the gallery';

  @override
  String get viewerClipGalleryDenied => 'No permission to save to the gallery';

  @override
  String get viewerClipExportNoSpace => 'Not enough space on the phone';

  @override
  String get viewerClipExportFailed => 'Couldn\'t export the clip';

  @override
  String get libraryTitle => 'Library';

  @override
  String get libraryChangeSession => 'Change session';

  @override
  String get librarySessionLatest => 'Latest session';

  @override
  String get librarySessionContinue => 'Continue';

  @override
  String get librarySessionNew => 'New session';

  @override
  String get librarySessionName => 'Name';

  @override
  String librarySessionDefaultName(String type, String date) {
    return '$type $date';
  }

  @override
  String get librarySessionTemplate => 'Tag template';

  @override
  String get librarySessionStart => 'Start session';

  @override
  String get librarySessionTypeMatch => 'Match';

  @override
  String get librarySessionTypeTraining => 'Training';

  @override
  String get librarySessionTypeOther => 'Other';

  @override
  String librarySessionClips(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips',
      one: '1 clip',
      zero: 'no clips',
    );
    return '$_temp0';
  }

  @override
  String get librarySessionClipsEmpty => 'No clips in this session.';

  @override
  String get libraryEmpty => 'No sessions yet.';

  @override
  String librarySelected(int count) {
    return '$count selected';
  }

  @override
  String get librarySelectAll => 'Select all';

  @override
  String get libraryExport => 'Export';

  @override
  String get libraryExportJoinedGallery => 'One video → gallery';

  @override
  String get libraryExportJoinedShare => 'One video → share';

  @override
  String get libraryExportZip => 'ZIP with separate videos';

  @override
  String get libraryExporting => 'Exporting…';

  @override
  String libraryWatchAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Watch all ($count)',
      one: 'Watch 1 clip',
    );
    return '$_temp0';
  }

  @override
  String get libraryDelete => 'Delete';

  @override
  String libraryDeleteClipsConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count clips? This can\'t be undone.',
      one: 'Delete 1 clip? This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteSession => 'Delete session';

  @override
  String libraryDeleteSessionConfirm(String name) {
    return 'Delete \"$name\" and all its clips? This can\'t be undone.';
  }

  @override
  String get libraryTemplatesTitle => 'Tag templates';

  @override
  String get libraryTemplateBuiltIn => 'Built-in';

  @override
  String get libraryTemplateExport => 'Copy as JSON';

  @override
  String get libraryTemplateExported => 'Template copied to the clipboard';

  @override
  String get libraryTemplateImport => 'Import JSON';

  @override
  String get libraryTemplateImportHint =>
      'Paste a template exported from InstantReplay';

  @override
  String libraryTemplateImported(String name) {
    return '\"$name\" imported';
  }

  @override
  String libraryTemplateImportError(String reason) {
    return 'Not a valid template: $reason';
  }

  @override
  String get libraryTemplateDelete => 'Delete template';

  @override
  String get libraryTemplateFootball => 'Football';

  @override
  String get libraryTemplateBasketball => 'Basketball';

  @override
  String get libraryTemplateHandball => 'Handball';

  @override
  String get libraryTemplateHockey => 'Hockey';

  @override
  String get libraryTemplateGeneric => 'Generic';

  @override
  String get libraryTemplateMigrated => 'My tags';

  @override
  String get libraryTagAttack => 'Attack';

  @override
  String get libraryTagDefense => 'Defence';

  @override
  String get libraryTagTransition => 'Transition';

  @override
  String get libraryTagSetPiece => 'Set piece';

  @override
  String get libraryTagGoal => 'Goal';

  @override
  String get libraryTagShot => 'Shot';

  @override
  String get libraryTagFoul => 'Foul';

  @override
  String get libraryTagCorner => 'Corner';

  @override
  String get libraryTagFreeKick => 'Free kick';

  @override
  String get libraryTagTurnover => 'Turnover';

  @override
  String get libraryTagBasket => 'Basket';

  @override
  String get libraryTagThreePointer => '3-pointer';

  @override
  String get libraryTagRebound => 'Rebound';

  @override
  String get libraryTagSteal => 'Steal';

  @override
  String get libraryTagSave => 'Save';

  @override
  String get libraryTagSevenMeters => '7 m throw';

  @override
  String get libraryTagPenalty => 'Penalty';

  @override
  String get viewerNearbyTitle => 'Cameras on this network';

  @override
  String get viewerNearbySearching => 'Looking for cameras…';

  @override
  String get viewerNearbyIncompatible => 'Different InstantReplay version';

  @override
  String get viewerNearbyOther => 'Or connect another way';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSaveSection => 'Save button';

  @override
  String get settingsDefaultDuration => 'Default duration';

  @override
  String get settingsQuickPresets => 'Quick buttons';

  @override
  String settingsQuickPresetsHint(int max) {
    return 'Choose up to $max. Each one saves at once with its own duration.';
  }

  @override
  String settingsPostRoll(int seconds) {
    return 'Post-roll: $seconds s';
  }

  @override
  String get settingsPostRollHint =>
      'Seconds still recorded after you tap Save.';

  @override
  String get settingsDisplaySection => 'Display';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsStorageSection => 'Storage';

  @override
  String get settingsStorageClips => 'Saved clips';

  @override
  String settingsStorageUsage(String size, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips',
      one: '1 clip',
    );
    return '$size in $_temp0';
  }

  @override
  String get settingsStorageUnavailable => 'Could not read the storage used.';

  @override
  String viewerClipDeleted(String name) {
    return '$name deleted';
  }

  @override
  String get viewerClipUndo => 'Undo';

  @override
  String get viewerTagPanelTitle => 'Tag this play';

  @override
  String get viewerTagPanelClose => 'Close';

  @override
  String get cameraMode => 'Mode';

  @override
  String get cameraModeReplay => 'Replay';

  @override
  String get cameraModeBroadcast => 'Broadcast (beta)';

  @override
  String get cameraModeBroadcastHint =>
      'Experimental: streams to YouTube Live with a scoreboard that viewers control. Clips keep working.';

  @override
  String get cameraModeLocked =>
      'Stop the stream to change the mode or the profile.';

  @override
  String get broadcastTitle => 'YouTube stream';

  @override
  String get broadcastStateIdle => 'Off air';

  @override
  String get broadcastStateConnecting => 'Connecting…';

  @override
  String get broadcastStateLive => 'Live';

  @override
  String get broadcastStateReconnecting => 'Reconnecting…';

  @override
  String get broadcastStateFailed => 'Failed';

  @override
  String get broadcastNotConfigured => 'Enter the stream key first';

  @override
  String broadcastReady(int kbps) {
    return 'Ready · $kbps kbps';
  }

  @override
  String broadcastBitrate(String mbps) {
    return '$mbps Mbps';
  }

  @override
  String get broadcastStart => 'Go live';

  @override
  String get broadcastStop => 'Stop';

  @override
  String get broadcastStopTitle => 'Stop the stream?';

  @override
  String get broadcastStopBody =>
      'The YouTube stream ends for everyone watching it.';

  @override
  String get broadcastStopKeep => 'Keep streaming';

  @override
  String get broadcastSettings => 'Stream settings';

  @override
  String get broadcastServer => 'Server';

  @override
  String get broadcastKey => 'Stream key';

  @override
  String broadcastKeyKeep(String hint) {
    return 'Leave empty to keep •••• $hint';
  }

  @override
  String get broadcastKeyHelp =>
      'In YouTube Studio: Create > Go live > Stream key.';

  @override
  String get broadcastKeyShow => 'Show the key';

  @override
  String get broadcastKeyHide => 'Hide the key';

  @override
  String get broadcastPaste => 'Paste';

  @override
  String broadcastBitrateLabel(int kbps) {
    return 'Video bitrate: $kbps kbps';
  }

  @override
  String get broadcastAudio => 'Sound from the microphone';

  @override
  String get broadcastCancel => 'Cancel';

  @override
  String get broadcastSave => 'Save';

  @override
  String broadcastFailed(String message) {
    return 'Could not stream: $message';
  }

  @override
  String get broadcastMicDenied =>
      'Microphone not allowed: streaming without sound';

  @override
  String get broadcastNotBroadcastMode => 'The camera is not in broadcast mode';

  @override
  String get scoreboardTitle => 'Scoreboard';

  @override
  String scoreboardHalf(int period) {
    return '${period}H';
  }

  @override
  String scoreboardPlus(String team) {
    return 'Add a point to $team';
  }

  @override
  String scoreboardMinus(String team) {
    return 'Take a point from $team';
  }

  @override
  String get scoreboardStartClock => 'Start the clock';

  @override
  String get scoreboardPauseClock => 'Stop the clock';

  @override
  String get scoreboardSetClock => 'Set the clock';

  @override
  String get scoreboardHoldToSetClock => 'Press and hold the clock to set it';

  @override
  String get scoreboardMinutes => 'Minutes';

  @override
  String get scoreboardSeconds => 'Seconds';

  @override
  String get scoreboardMore => 'Period, show and settings';

  @override
  String get scoreboardHidden => 'Scoreboard hidden';

  @override
  String scoreboardGoToPeriod(String period) {
    return 'Go to $period';
  }

  @override
  String scoreboardBackToPeriod(String period) {
    return 'Back to $period';
  }

  @override
  String scoreboardPeriodConfirmTitle(String period) {
    return 'Go to $period?';
  }

  @override
  String scoreboardPeriodConfirmBody(String time) {
    return 'The clock stops and goes to $time.';
  }

  @override
  String get scoreboardPeriodConfirm => 'Change period';

  @override
  String get scoreboardSet => 'Set';

  @override
  String get scoreboardVisible => 'On screen';

  @override
  String get scoreboardReset => 'Reset';

  @override
  String get scoreboardResetTitle => 'Reset the scoreboard?';

  @override
  String get scoreboardResetBody =>
      'Scores back to 0, first period and the clock reset. Team names and settings stay.';

  @override
  String get scoreboardSettings => 'Scoreboard settings';

  @override
  String get scoreboardHome => 'Home';

  @override
  String get scoreboardAway => 'Away';

  @override
  String get scoreboardTeamName => 'Name (up to 5 letters)';

  @override
  String scoreboardTeamColor(String team) {
    return 'Color of $team';
  }

  @override
  String get scoreboardPeriods => 'Periods';

  @override
  String get scoreboardPeriodMinutes => 'Minutes per period';

  @override
  String get scoreboardClockDirection => 'Clock';

  @override
  String get scoreboardCountUp => 'Counts up';

  @override
  String get scoreboardCountDown => 'Counts down';
}
