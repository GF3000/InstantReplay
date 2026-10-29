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
  String get viewerComingSoon => 'The Viewer screen arrives in M4.';

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
  String viewerStatusBuffer(int seconds) {
    return 'buffer $seconds s';
  }

  @override
  String viewerStatusOutbox(int clips) {
    return 'outbox $clips';
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
  String viewerClipTitle(int number, int seconds) {
    return 'Clip $number · $seconds s';
  }

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
  String get viewerReviewNextFrame => 'Next frame';

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
}
