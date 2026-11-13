import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'InstantReplay'**
  String get appTitle;

  /// No description provided for @roleGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a role'**
  String get roleGateTitle;

  /// No description provided for @roleGateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This device will remember it. You can switch later.'**
  String get roleGateSubtitle;

  /// No description provided for @roleCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get roleCamera;

  /// No description provided for @roleCameraDescription.
  ///
  /// In en, this message translates to:
  /// **'Records the game and keeps the replay buffer.'**
  String get roleCameraDescription;

  /// No description provided for @roleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get roleViewer;

  /// No description provided for @roleViewerDescription.
  ///
  /// In en, this message translates to:
  /// **'Watches live and saves the plays.'**
  String get roleViewerDescription;

  /// No description provided for @labEntry.
  ///
  /// In en, this message translates to:
  /// **'Lab (Phase 0 harness)'**
  String get labEntry;

  /// No description provided for @labUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The lab is only available on Android.'**
  String get labUnavailable;

  /// No description provided for @switchRole.
  ///
  /// In en, this message translates to:
  /// **'Switch role'**
  String get switchRole;

  /// No description provided for @cameraStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting the camera…'**
  String get cameraStarting;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'InstantReplay needs camera permission to record.'**
  String get cameraPermissionDenied;

  /// No description provided for @cameraNoProfiles.
  ///
  /// In en, this message translates to:
  /// **'This device has no supported recording quality.'**
  String get cameraNoProfiles;

  /// No description provided for @cameraStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The camera could not start: {error}'**
  String cameraStartFailed(String error);

  /// No description provided for @cameraRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get cameraRetry;

  /// No description provided for @cameraProfile.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get cameraProfile;

  /// No description provided for @cameraStartOperating.
  ///
  /// In en, this message translates to:
  /// **'Start operating'**
  String get cameraStartOperating;

  /// No description provided for @cameraOperatingHint.
  ///
  /// In en, this message translates to:
  /// **'Tap anywhere to return to setup'**
  String get cameraOperatingHint;

  /// No description provided for @cameraOperatingStatus.
  ///
  /// In en, this message translates to:
  /// **'REC · buffer {seconds} s · outbox {clips} · {temperature}'**
  String cameraOperatingStatus(int seconds, int clips, String temperature);

  /// No description provided for @cameraWaitingForStats.
  ///
  /// In en, this message translates to:
  /// **'Waiting for statistics…'**
  String get cameraWaitingForStats;

  /// No description provided for @cameraStatCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraStatCamera;

  /// No description provided for @cameraStatFps.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get cameraStatFps;

  /// No description provided for @cameraFpsValue.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps'**
  String cameraFpsValue(String fps);

  /// No description provided for @cameraStatGaps.
  ///
  /// In en, this message translates to:
  /// **'Frame gaps'**
  String get cameraStatGaps;

  /// No description provided for @cameraGapsValue.
  ///
  /// In en, this message translates to:
  /// **'{total} (camera {camera}, GL {gl})'**
  String cameraGapsValue(int total, int camera, int gl);

  /// No description provided for @cameraStatBuffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get cameraStatBuffer;

  /// No description provided for @cameraBufferValue.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s · {megabytes} MB'**
  String cameraBufferValue(int seconds, String megabytes);

  /// No description provided for @cameraStatOutbox.
  ///
  /// In en, this message translates to:
  /// **'Outbox'**
  String get cameraStatOutbox;

  /// No description provided for @cameraOutboxValue.
  ///
  /// In en, this message translates to:
  /// **'{clips, plural, =1{1 clip} other{{clips} clips}} · {megabytes} MB'**
  String cameraOutboxValue(int clips, String megabytes);

  /// No description provided for @cameraStatThermal.
  ///
  /// In en, this message translates to:
  /// **'Thermal status'**
  String get cameraStatThermal;

  /// No description provided for @cameraStatBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get cameraStatBattery;

  /// No description provided for @cameraBatteryValue.
  ///
  /// In en, this message translates to:
  /// **'{temperature} · {percent} · {power}'**
  String cameraBatteryValue(String temperature, String percent, String power);

  /// No description provided for @cameraCharging.
  ///
  /// In en, this message translates to:
  /// **'charging'**
  String get cameraCharging;

  /// No description provided for @cameraNotCharging.
  ///
  /// In en, this message translates to:
  /// **'not charging'**
  String get cameraNotCharging;

  /// No description provided for @cameraNotChargingWarning.
  ///
  /// In en, this message translates to:
  /// **'Not charging. Connect power for long sessions.'**
  String get cameraNotChargingWarning;

  /// No description provided for @cameraNotificationsDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off, so Android will not show the recording notice. Recording still works.'**
  String get cameraNotificationsDenied;

  /// No description provided for @cameraErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera errors'**
  String get cameraErrorsTitle;

  /// No description provided for @cameraDismissErrors.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get cameraDismissErrors;

  /// No description provided for @cameraSaveTestClip.
  ///
  /// In en, this message translates to:
  /// **'Save test clip (last 20 s)'**
  String get cameraSaveTestClip;

  /// No description provided for @cameraTestClipSaved.
  ///
  /// In en, this message translates to:
  /// **'Test clip saved: {seconds} s, {megabytes} MB'**
  String cameraTestClipSaved(String seconds, String megabytes);

  /// No description provided for @cameraTestClipFailed.
  ///
  /// In en, this message translates to:
  /// **'Test clip failed: {error}'**
  String cameraTestClipFailed(String error);

  /// No description provided for @thermalNone.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get thermalNone;

  /// No description provided for @thermalLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get thermalLight;

  /// No description provided for @thermalModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate'**
  String get thermalModerate;

  /// No description provided for @thermalSevere.
  ///
  /// In en, this message translates to:
  /// **'Severe'**
  String get thermalSevere;

  /// No description provided for @thermalCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get thermalCritical;

  /// No description provided for @thermalEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get thermalEmergency;

  /// No description provided for @thermalShutdown.
  ///
  /// In en, this message translates to:
  /// **'Shutdown'**
  String get thermalShutdown;

  /// No description provided for @viewerConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to the camera'**
  String get viewerConnectTitle;

  /// No description provided for @viewerAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Camera address'**
  String get viewerAddressLabel;

  /// No description provided for @viewerAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an address like http://192.168.1.20:8080'**
  String get viewerAddressInvalid;

  /// No description provided for @viewerAddressSubmit.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get viewerAddressSubmit;

  /// No description provided for @viewerScanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get viewerScanQr;

  /// No description provided for @viewerScanHint.
  ///
  /// In en, this message translates to:
  /// **'Point at the QR shown on the camera'**
  String get viewerScanHint;

  /// No description provided for @viewerScanNotCamera.
  ///
  /// In en, this message translates to:
  /// **'This QR is not from an InstantReplay camera. Keep pointing at the camera\'s QR.'**
  String get viewerScanNotCamera;

  /// No description provided for @viewerScanPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'No camera permission. Type the address, or allow the camera in Settings.'**
  String get viewerScanPermissionDenied;

  /// No description provided for @viewerCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shown on the camera'**
  String get viewerCodeTitle;

  /// No description provided for @viewerCameraAt.
  ///
  /// In en, this message translates to:
  /// **'Camera at {address}'**
  String viewerCameraAt(String address);

  /// No description provided for @viewerCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get viewerCodeLabel;

  /// No description provided for @viewerCodeSubmit.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get viewerCodeSubmit;

  /// No description provided for @viewerCodeWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong code. Check the camera screen and try again.'**
  String get viewerCodeWrong;

  /// No description provided for @viewerCodeTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get viewerCodeTooManyAttempts;

  /// No description provided for @viewerCameraUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the camera. Check that both devices are on the same Wi-Fi.'**
  String get viewerCameraUnreachable;

  /// No description provided for @viewerSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'The camera started a new session. Enter its new code.'**
  String get viewerSessionExpired;

  /// No description provided for @viewerChangeCamera.
  ///
  /// In en, this message translates to:
  /// **'Change camera'**
  String get viewerChangeCamera;

  /// No description provided for @viewerLinkConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get viewerLinkConnecting;

  /// No description provided for @viewerLinkReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get viewerLinkReconnecting;

  /// No description provided for @viewerLinkIncompatible.
  ///
  /// In en, this message translates to:
  /// **'This camera runs another version of InstantReplay. Update both devices.'**
  String get viewerLinkIncompatible;

  /// No description provided for @viewerLiveStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting live view…'**
  String get viewerLiveStarting;

  /// No description provided for @viewerLiveInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Live view interrupted. Restarting…'**
  String get viewerLiveInterrupted;

  /// No description provided for @viewerLiveRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart live view'**
  String get viewerLiveRestart;

  /// No description provided for @viewerStatusRec.
  ///
  /// In en, this message translates to:
  /// **'REC'**
  String get viewerStatusRec;

  /// No description provided for @viewerStatusIdle.
  ///
  /// In en, this message translates to:
  /// **'Not recording'**
  String get viewerStatusIdle;

  /// No description provided for @viewerStatusFps.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps'**
  String viewerStatusFps(int fps);

  /// No description provided for @viewerStatusTemperature.
  ///
  /// In en, this message translates to:
  /// **'{celsius} °C'**
  String viewerStatusTemperature(String celsius);

  /// No description provided for @viewerSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE {seconds} s'**
  String viewerSave(int seconds);

  /// No description provided for @viewerSaveQuick.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String viewerSaveQuick(int seconds);

  /// No description provided for @viewerSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Saves the last seconds plus {seconds} s after the tap.'**
  String viewerSaveHint(int seconds);

  /// No description provided for @viewerSessionOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'Clips stay in this browser tab only. Download the ones you want to keep.'**
  String get viewerSessionOnlyNotice;

  /// No description provided for @viewerClipsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Saved clips appear here.'**
  String get viewerClipsEmpty;

  /// No description provided for @viewerClipRequesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting…'**
  String get viewerClipRequesting;

  /// No description provided for @viewerClipRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get viewerClipRecording;

  /// No description provided for @viewerClipDownloadingStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get viewerClipDownloadingStarted;

  /// No description provided for @viewerClipDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String viewerClipDownloading(int percent);

  /// No description provided for @viewerClipReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get viewerClipReady;

  /// No description provided for @viewerClipFailedRequest.
  ///
  /// In en, this message translates to:
  /// **'The camera did not answer'**
  String get viewerClipFailedRequest;

  /// No description provided for @viewerClipFailedDownload.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get viewerClipFailedDownload;

  /// No description provided for @viewerClipFailedChecksum.
  ///
  /// In en, this message translates to:
  /// **'The download was corrupted'**
  String get viewerClipFailedChecksum;

  /// No description provided for @viewerClipExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired on the camera'**
  String get viewerClipExpired;

  /// No description provided for @viewerClipRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get viewerClipRetry;

  /// No description provided for @viewerClipDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get viewerClipDownload;

  /// No description provided for @viewerReviewPrevFrame.
  ///
  /// In en, this message translates to:
  /// **'Previous frame'**
  String get viewerReviewPrevFrame;

  /// No description provided for @viewerReviewZoomReset.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get viewerReviewZoomReset;

  /// No description provided for @viewerReviewNextFrame.
  ///
  /// In en, this message translates to:
  /// **'Next frame'**
  String get viewerReviewNextFrame;

  /// No description provided for @viewerDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get viewerDraw;

  /// No description provided for @viewerDrawColor.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get viewerDrawColor;

  /// No description provided for @viewerDrawUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get viewerDrawUndo;

  /// No description provided for @viewerDrawClear.
  ///
  /// In en, this message translates to:
  /// **'Clear drawing'**
  String get viewerDrawClear;

  /// No description provided for @viewerDrawDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get viewerDrawDone;

  /// No description provided for @viewerDrawArrow.
  ///
  /// In en, this message translates to:
  /// **'Arrow'**
  String get viewerDrawArrow;

  /// No description provided for @viewerDrawCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get viewerDrawCircle;

  /// No description provided for @viewerDrawLine.
  ///
  /// In en, this message translates to:
  /// **'Straight line'**
  String get viewerDrawLine;

  /// No description provided for @viewerDrawPen.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get viewerDrawPen;

  /// No description provided for @viewerDrawSelect.
  ///
  /// In en, this message translates to:
  /// **'Select and move'**
  String get viewerDrawSelect;

  /// No description provided for @viewerDrawEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get viewerDrawEraser;

  /// No description provided for @viewerDrawDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete mark'**
  String get viewerDrawDelete;

  /// No description provided for @viewerDrawThick.
  ///
  /// In en, this message translates to:
  /// **'Thick line'**
  String get viewerDrawThick;

  /// No description provided for @viewerReviewPrevClip.
  ///
  /// In en, this message translates to:
  /// **'Previous clip'**
  String get viewerReviewPrevClip;

  /// No description provided for @viewerReviewNextClip.
  ///
  /// In en, this message translates to:
  /// **'Next clip'**
  String get viewerReviewNextClip;

  /// No description provided for @viewerReviewPlaylistRestart.
  ///
  /// In en, this message translates to:
  /// **'Watch all again'**
  String get viewerReviewPlaylistRestart;

  /// No description provided for @viewerReviewPlaylistPosition.
  ///
  /// In en, this message translates to:
  /// **'{index} / {count}'**
  String viewerReviewPlaylistPosition(int index, int count);

  /// No description provided for @viewerReviewPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get viewerReviewPlay;

  /// No description provided for @viewerReviewPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get viewerReviewPause;

  /// No description provided for @viewerReviewSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}×'**
  String viewerReviewSpeed(double speed);

  /// No description provided for @viewerReviewError.
  ///
  /// In en, this message translates to:
  /// **'This clip cannot be played here.'**
  String get viewerReviewError;

  /// No description provided for @cameraPairingTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect a viewer'**
  String get cameraPairingTitle;

  /// No description provided for @cameraPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get cameraPairingCode;

  /// No description provided for @cameraPairingScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code, or open this address in a browser on the same Wi-Fi:'**
  String get cameraPairingScanHint;

  /// No description provided for @cameraPairingNoNetwork.
  ///
  /// In en, this message translates to:
  /// **'No Wi-Fi or hotspot found. Turn on the hotspot or join a Wi-Fi network.'**
  String get cameraPairingNoNetwork;

  /// No description provided for @cameraViewersConnected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No viewers connected} =1{1 viewer connected} other{{count} viewers connected}}'**
  String cameraViewersConnected(int count);

  /// No description provided for @cameraOperatingViewers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 viewer} other{{count} viewers}}'**
  String cameraOperatingViewers(int count);

  /// No description provided for @serverStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting the viewer server…'**
  String get serverStarting;

  /// No description provided for @serverStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The viewer server could not start: {error}'**
  String serverStartFailed(String error);

  /// No description provided for @viewerStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera status'**
  String get viewerStatusTitle;

  /// No description provided for @viewerStatusRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get viewerStatusRecording;

  /// No description provided for @viewerStatusFpsLabel.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get viewerStatusFpsLabel;

  /// No description provided for @viewerStatusBufferLabel.
  ///
  /// In en, this message translates to:
  /// **'Replay buffer'**
  String get viewerStatusBufferLabel;

  /// No description provided for @viewerStatusSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String viewerStatusSeconds(int seconds);

  /// No description provided for @viewerStatusPendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Clips pending on the camera'**
  String get viewerStatusPendingLabel;

  /// No description provided for @viewerStatusTemperatureLabel.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get viewerStatusTemperatureLabel;

  /// No description provided for @viewerStatusBatteryLabel.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get viewerStatusBatteryLabel;

  /// No description provided for @viewerStatusBatteryPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String viewerStatusBatteryPercent(int percent);

  /// No description provided for @viewerStatusCharging.
  ///
  /// In en, this message translates to:
  /// **'charging'**
  String get viewerStatusCharging;

  /// No description provided for @viewerStatusNotCharging.
  ///
  /// In en, this message translates to:
  /// **'not charging'**
  String get viewerStatusNotCharging;

  /// No description provided for @viewerProblemDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get viewerProblemDisconnected;

  /// No description provided for @viewerProblemHot.
  ///
  /// In en, this message translates to:
  /// **'Overheating'**
  String get viewerProblemHot;

  /// No description provided for @viewerProblemBatteryLow.
  ///
  /// In en, this message translates to:
  /// **'Battery {percent}%'**
  String viewerProblemBatteryLow(int percent);

  /// No description provided for @viewerClipName.
  ///
  /// In en, this message translates to:
  /// **'{tag} · {time}'**
  String viewerClipName(String tag, String time);

  /// No description provided for @viewerClipUntagged.
  ///
  /// In en, this message translates to:
  /// **'Clip · {time}'**
  String viewerClipUntagged(String time);

  /// No description provided for @viewerClipDuration.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String viewerClipDuration(int seconds);

  /// No description provided for @viewerClipChangeTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get viewerClipChangeTag;

  /// No description provided for @viewerClipNoTag.
  ///
  /// In en, this message translates to:
  /// **'No tag'**
  String get viewerClipNoTag;

  /// No description provided for @viewerFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get viewerFilterAll;

  /// No description provided for @viewerTagDefaultGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get viewerTagDefaultGood;

  /// No description provided for @viewerTagDefaultBad.
  ///
  /// In en, this message translates to:
  /// **'Bad'**
  String get viewerTagDefaultBad;

  /// No description provided for @viewerTagDefaultOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get viewerTagDefaultOther;

  /// No description provided for @viewerTagsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit tags'**
  String get viewerTagsEdit;

  /// No description provided for @viewerTagsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get viewerTagsTitle;

  /// No description provided for @viewerTagsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get viewerTagsAdd;

  /// No description provided for @viewerTagsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tags. Add one to label your clips.'**
  String get viewerTagsEmpty;

  /// No description provided for @viewerTagEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get viewerTagEdit;

  /// No description provided for @viewerTagName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get viewerTagName;

  /// No description provided for @viewerTagColor.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get viewerTagColor;

  /// No description provided for @viewerTagDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get viewerTagDelete;

  /// No description provided for @viewerTagCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get viewerTagCancel;

  /// No description provided for @viewerTagOk.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get viewerTagOk;

  /// No description provided for @cameraAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get cameraAdvanced;

  /// No description provided for @cameraHotWarning.
  ///
  /// In en, this message translates to:
  /// **'The phone is hot ({level}). Shade it or lower the quality.'**
  String cameraHotWarning(String level);

  /// No description provided for @viewerTagDeleted.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" deleted'**
  String viewerTagDeleted(String name);

  /// No description provided for @viewerTagUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get viewerTagUndo;

  /// No description provided for @recTitle.
  ///
  /// In en, this message translates to:
  /// **'Full recording'**
  String get recTitle;

  /// No description provided for @recRecord.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get recRecord;

  /// No description provided for @recResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get recResume;

  /// No description provided for @recPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get recPause;

  /// No description provided for @recFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get recFinish;

  /// No description provided for @recOptions.
  ///
  /// In en, this message translates to:
  /// **'Recording options'**
  String get recOptions;

  /// No description provided for @recFromNow.
  ///
  /// In en, this message translates to:
  /// **'Record from now'**
  String get recFromNow;

  /// No description provided for @recResumeFromNow.
  ///
  /// In en, this message translates to:
  /// **'Resume from now'**
  String get recResumeFromNow;

  /// No description provided for @recIncludeLast.
  ///
  /// In en, this message translates to:
  /// **'Record including the last {seconds} s'**
  String recIncludeLast(int seconds);

  /// No description provided for @recResumeIncludeLast.
  ///
  /// In en, this message translates to:
  /// **'Resume including the last {seconds} s'**
  String recResumeIncludeLast(int seconds);

  /// No description provided for @recIdle.
  ///
  /// In en, this message translates to:
  /// **'Not recording'**
  String get recIdle;

  /// No description provided for @recPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused · {elapsed}'**
  String recPaused(String elapsed);

  /// No description provided for @recPart.
  ///
  /// In en, this message translates to:
  /// **'part {part}'**
  String recPart(int part);

  /// No description provided for @recRemaining.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String recRemaining(String time);

  /// No description provided for @recLowSpace.
  ///
  /// In en, this message translates to:
  /// **'Low space: {time} left'**
  String recLowSpace(String time);

  /// No description provided for @recLowSpaceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Low space on the camera'**
  String get recLowSpaceUnknown;

  /// No description provided for @recFree.
  ///
  /// In en, this message translates to:
  /// **'{gigabytes} GB free'**
  String recFree(String gigabytes);

  /// No description provided for @recFinishTitle.
  ///
  /// In en, this message translates to:
  /// **'Finish the recording?'**
  String get recFinishTitle;

  /// No description provided for @recFinishBody.
  ///
  /// In en, this message translates to:
  /// **'The {elapsed} recorded will be saved to the camera\'s gallery (Movies/InstantReplay).'**
  String recFinishBody(String elapsed);

  /// No description provided for @recFinishKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep recording'**
  String get recFinishKeep;

  /// No description provided for @recSaved.
  ///
  /// In en, this message translates to:
  /// **'{parts, plural, =1{Recording saved to the camera\'s gallery ({duration})} other{Recording saved to the camera\'s gallery ({duration}, {parts} parts)}}'**
  String recSaved(int parts, String duration);

  /// No description provided for @recSavedLowSpace.
  ///
  /// In en, this message translates to:
  /// **'The camera ran out of space: the recording stopped and was saved ({duration})'**
  String recSavedLowSpace(String duration);

  /// No description provided for @recSavedError.
  ///
  /// In en, this message translates to:
  /// **'The recording stopped because of an error; what was recorded is saved ({duration})'**
  String recSavedError(String duration);

  /// No description provided for @recRecovered.
  ///
  /// In en, this message translates to:
  /// **'Recovered a {duration} recording'**
  String recRecovered(String duration);

  /// No description provided for @recRecoveredHint.
  ///
  /// In en, this message translates to:
  /// **'It was left open when the app closed. It is in the gallery (Movies/InstantReplay).'**
  String get recRecoveredHint;

  /// No description provided for @recNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough space on the camera to record (it needs 1 GB free)'**
  String get recNoSpace;

  /// No description provided for @recFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording failed: {message}'**
  String recFailed(String message);

  /// No description provided for @viewerClipSaveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get viewerClipSaveToGallery;

  /// No description provided for @viewerClipShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get viewerClipShare;

  /// No description provided for @viewerClipSavedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to the gallery'**
  String get viewerClipSavedToGallery;

  /// No description provided for @viewerClipGalleryDenied.
  ///
  /// In en, this message translates to:
  /// **'No permission to save to the gallery'**
  String get viewerClipGalleryDenied;

  /// No description provided for @viewerClipExportNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough space on the phone'**
  String get viewerClipExportNoSpace;

  /// No description provided for @viewerClipExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export the clip'**
  String get viewerClipExportFailed;

  /// No description provided for @libraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// No description provided for @libraryChangeSession.
  ///
  /// In en, this message translates to:
  /// **'Change session'**
  String get libraryChangeSession;

  /// No description provided for @librarySessionLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest session'**
  String get librarySessionLatest;

  /// No description provided for @librarySessionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get librarySessionContinue;

  /// No description provided for @librarySessionNew.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get librarySessionNew;

  /// No description provided for @librarySessionName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get librarySessionName;

  /// No description provided for @librarySessionDefaultName.
  ///
  /// In en, this message translates to:
  /// **'{type} {date}'**
  String librarySessionDefaultName(String type, String date);

  /// No description provided for @librarySessionTemplate.
  ///
  /// In en, this message translates to:
  /// **'Tag template'**
  String get librarySessionTemplate;

  /// No description provided for @librarySessionStart.
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get librarySessionStart;

  /// No description provided for @librarySessionTypeMatch.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get librarySessionTypeMatch;

  /// No description provided for @librarySessionTypeTraining.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get librarySessionTypeTraining;

  /// No description provided for @librarySessionTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get librarySessionTypeOther;

  /// No description provided for @librarySessionClips.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no clips} =1{1 clip} other{{count} clips}}'**
  String librarySessionClips(int count);

  /// No description provided for @librarySessionClipsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No clips in this session.'**
  String get librarySessionClipsEmpty;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet.'**
  String get libraryEmpty;

  /// No description provided for @librarySelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String librarySelected(int count);

  /// No description provided for @librarySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get librarySelectAll;

  /// No description provided for @libraryExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get libraryExport;

  /// No description provided for @libraryExportJoinedGallery.
  ///
  /// In en, this message translates to:
  /// **'One video → gallery'**
  String get libraryExportJoinedGallery;

  /// No description provided for @libraryExportJoinedShare.
  ///
  /// In en, this message translates to:
  /// **'One video → share'**
  String get libraryExportJoinedShare;

  /// No description provided for @libraryExportZip.
  ///
  /// In en, this message translates to:
  /// **'ZIP with separate videos'**
  String get libraryExportZip;

  /// No description provided for @libraryExporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get libraryExporting;

  /// No description provided for @libraryWatchAll.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Watch 1 clip} other{Watch all ({count})}}'**
  String libraryWatchAll(int count);

  /// No description provided for @libraryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get libraryDelete;

  /// No description provided for @libraryDeleteClipsConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 clip? This can\'t be undone.} other{Delete {count} clips? This can\'t be undone.}}'**
  String libraryDeleteClipsConfirm(int count);

  /// No description provided for @libraryDeleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get libraryDeleteSession;

  /// No description provided for @libraryDeleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" and all its clips? This can\'t be undone.'**
  String libraryDeleteSessionConfirm(String name);

  /// No description provided for @libraryTemplatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag templates'**
  String get libraryTemplatesTitle;

  /// No description provided for @libraryTemplateBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get libraryTemplateBuiltIn;

  /// No description provided for @libraryTemplateExport.
  ///
  /// In en, this message translates to:
  /// **'Copy as JSON'**
  String get libraryTemplateExport;

  /// No description provided for @libraryTemplateExported.
  ///
  /// In en, this message translates to:
  /// **'Template copied to the clipboard'**
  String get libraryTemplateExported;

  /// No description provided for @libraryTemplateImport.
  ///
  /// In en, this message translates to:
  /// **'Import JSON'**
  String get libraryTemplateImport;

  /// No description provided for @libraryTemplateImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a template exported from InstantReplay'**
  String get libraryTemplateImportHint;

  /// No description provided for @libraryTemplateImported.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" imported'**
  String libraryTemplateImported(String name);

  /// No description provided for @libraryTemplateImportError.
  ///
  /// In en, this message translates to:
  /// **'Not a valid template: {reason}'**
  String libraryTemplateImportError(String reason);

  /// No description provided for @libraryTemplateDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get libraryTemplateDelete;

  /// No description provided for @libraryTemplateFootball.
  ///
  /// In en, this message translates to:
  /// **'Football'**
  String get libraryTemplateFootball;

  /// No description provided for @libraryTemplateBasketball.
  ///
  /// In en, this message translates to:
  /// **'Basketball'**
  String get libraryTemplateBasketball;

  /// No description provided for @libraryTemplateHandball.
  ///
  /// In en, this message translates to:
  /// **'Handball'**
  String get libraryTemplateHandball;

  /// No description provided for @libraryTemplateHockey.
  ///
  /// In en, this message translates to:
  /// **'Hockey'**
  String get libraryTemplateHockey;

  /// No description provided for @libraryTemplateGeneric.
  ///
  /// In en, this message translates to:
  /// **'Generic'**
  String get libraryTemplateGeneric;

  /// No description provided for @libraryTemplateMigrated.
  ///
  /// In en, this message translates to:
  /// **'My tags'**
  String get libraryTemplateMigrated;

  /// No description provided for @libraryTagAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get libraryTagAttack;

  /// No description provided for @libraryTagDefense.
  ///
  /// In en, this message translates to:
  /// **'Defence'**
  String get libraryTagDefense;

  /// No description provided for @libraryTagTransition.
  ///
  /// In en, this message translates to:
  /// **'Transition'**
  String get libraryTagTransition;

  /// No description provided for @libraryTagSetPiece.
  ///
  /// In en, this message translates to:
  /// **'Set piece'**
  String get libraryTagSetPiece;

  /// No description provided for @libraryTagGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get libraryTagGoal;

  /// No description provided for @libraryTagShot.
  ///
  /// In en, this message translates to:
  /// **'Shot'**
  String get libraryTagShot;

  /// No description provided for @libraryTagFoul.
  ///
  /// In en, this message translates to:
  /// **'Foul'**
  String get libraryTagFoul;

  /// No description provided for @libraryTagCorner.
  ///
  /// In en, this message translates to:
  /// **'Corner'**
  String get libraryTagCorner;

  /// No description provided for @libraryTagFreeKick.
  ///
  /// In en, this message translates to:
  /// **'Free kick'**
  String get libraryTagFreeKick;

  /// No description provided for @libraryTagTurnover.
  ///
  /// In en, this message translates to:
  /// **'Turnover'**
  String get libraryTagTurnover;

  /// No description provided for @libraryTagBasket.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get libraryTagBasket;

  /// No description provided for @libraryTagThreePointer.
  ///
  /// In en, this message translates to:
  /// **'3-pointer'**
  String get libraryTagThreePointer;

  /// No description provided for @libraryTagRebound.
  ///
  /// In en, this message translates to:
  /// **'Rebound'**
  String get libraryTagRebound;

  /// No description provided for @libraryTagSteal.
  ///
  /// In en, this message translates to:
  /// **'Steal'**
  String get libraryTagSteal;

  /// No description provided for @libraryTagSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get libraryTagSave;

  /// No description provided for @libraryTagSevenMeters.
  ///
  /// In en, this message translates to:
  /// **'7 m throw'**
  String get libraryTagSevenMeters;

  /// No description provided for @libraryTagPenalty.
  ///
  /// In en, this message translates to:
  /// **'Penalty'**
  String get libraryTagPenalty;

  /// No description provided for @viewerNearbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Cameras on this network'**
  String get viewerNearbyTitle;

  /// No description provided for @viewerNearbySearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for cameras…'**
  String get viewerNearbySearching;

  /// No description provided for @viewerNearbyIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Different InstantReplay version'**
  String get viewerNearbyIncompatible;

  /// No description provided for @viewerNearbyOther.
  ///
  /// In en, this message translates to:
  /// **'Or connect another way'**
  String get viewerNearbyOther;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSaveSection.
  ///
  /// In en, this message translates to:
  /// **'Save button'**
  String get settingsSaveSection;

  /// No description provided for @settingsDefaultDuration.
  ///
  /// In en, this message translates to:
  /// **'Default duration'**
  String get settingsDefaultDuration;

  /// No description provided for @settingsQuickPresets.
  ///
  /// In en, this message translates to:
  /// **'Quick buttons'**
  String get settingsQuickPresets;

  /// No description provided for @settingsQuickPresetsHint.
  ///
  /// In en, this message translates to:
  /// **'Choose up to {max}. Each one saves at once with its own duration.'**
  String settingsQuickPresetsHint(int max);

  /// No description provided for @settingsPostRoll.
  ///
  /// In en, this message translates to:
  /// **'Post-roll: {seconds} s'**
  String settingsPostRoll(int seconds);

  /// No description provided for @settingsPostRollHint.
  ///
  /// In en, this message translates to:
  /// **'Seconds still recorded after you tap Save.'**
  String get settingsPostRollHint;

  /// No description provided for @settingsDisplaySection.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsDisplaySection;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsStorageSection.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorageSection;

  /// No description provided for @settingsStorageClips.
  ///
  /// In en, this message translates to:
  /// **'Saved clips'**
  String get settingsStorageClips;

  /// No description provided for @settingsStorageUsage.
  ///
  /// In en, this message translates to:
  /// **'{size} in {count, plural, =1{1 clip} other{{count} clips}}'**
  String settingsStorageUsage(String size, int count);

  /// No description provided for @settingsStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the storage used.'**
  String get settingsStorageUnavailable;

  /// SnackBar after swiping a clip away; name is the clip name, e.g. 'Good · 12:41'.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String viewerClipDeleted(String name);

  /// No description provided for @viewerClipUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get viewerClipUndo;

  /// No description provided for @viewerTagPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Tag this play'**
  String get viewerTagPanelTitle;

  /// No description provided for @viewerTagPanelClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get viewerTagPanelClose;

  /// No description provided for @cameraMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get cameraMode;

  /// No description provided for @cameraModeReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get cameraModeReplay;

  /// No description provided for @cameraModeBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcast (beta)'**
  String get cameraModeBroadcast;

  /// No description provided for @cameraModeBroadcastHint.
  ///
  /// In en, this message translates to:
  /// **'Experimental: streams to YouTube Live with a scoreboard that viewers control. Clips keep working.'**
  String get cameraModeBroadcastHint;

  /// No description provided for @cameraModeLocked.
  ///
  /// In en, this message translates to:
  /// **'Stop the stream to change the mode or the profile.'**
  String get cameraModeLocked;

  /// No description provided for @broadcastTitle.
  ///
  /// In en, this message translates to:
  /// **'YouTube stream'**
  String get broadcastTitle;

  /// No description provided for @broadcastStateIdle.
  ///
  /// In en, this message translates to:
  /// **'Off air'**
  String get broadcastStateIdle;

  /// No description provided for @broadcastStateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get broadcastStateConnecting;

  /// No description provided for @broadcastStateLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get broadcastStateLive;

  /// No description provided for @broadcastStateReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get broadcastStateReconnecting;

  /// No description provided for @broadcastStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get broadcastStateFailed;

  /// No description provided for @broadcastNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Enter the stream key first'**
  String get broadcastNotConfigured;

  /// No description provided for @broadcastReady.
  ///
  /// In en, this message translates to:
  /// **'Ready · {kbps} kbps'**
  String broadcastReady(int kbps);

  /// No description provided for @broadcastBitrate.
  ///
  /// In en, this message translates to:
  /// **'{mbps} Mbps'**
  String broadcastBitrate(String mbps);

  /// No description provided for @broadcastStart.
  ///
  /// In en, this message translates to:
  /// **'Go live'**
  String get broadcastStart;

  /// No description provided for @broadcastStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get broadcastStop;

  /// No description provided for @broadcastStopTitle.
  ///
  /// In en, this message translates to:
  /// **'Stop the stream?'**
  String get broadcastStopTitle;

  /// No description provided for @broadcastStopBody.
  ///
  /// In en, this message translates to:
  /// **'The YouTube stream ends for everyone watching it.'**
  String get broadcastStopBody;

  /// No description provided for @broadcastStopKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep streaming'**
  String get broadcastStopKeep;

  /// No description provided for @broadcastSettings.
  ///
  /// In en, this message translates to:
  /// **'Stream settings'**
  String get broadcastSettings;

  /// No description provided for @broadcastServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get broadcastServer;

  /// No description provided for @broadcastKey.
  ///
  /// In en, this message translates to:
  /// **'Stream key'**
  String get broadcastKey;

  /// No description provided for @broadcastKeyKeep.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep •••• {hint}'**
  String broadcastKeyKeep(String hint);

  /// No description provided for @broadcastKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'In YouTube Studio: Create > Go live > Stream key.'**
  String get broadcastKeyHelp;

  /// No description provided for @broadcastKeyShow.
  ///
  /// In en, this message translates to:
  /// **'Show the key'**
  String get broadcastKeyShow;

  /// No description provided for @broadcastKeyHide.
  ///
  /// In en, this message translates to:
  /// **'Hide the key'**
  String get broadcastKeyHide;

  /// No description provided for @broadcastPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get broadcastPaste;

  /// No description provided for @broadcastBitrateLabel.
  ///
  /// In en, this message translates to:
  /// **'Video bitrate: {kbps} kbps'**
  String broadcastBitrateLabel(int kbps);

  /// No description provided for @broadcastAudio.
  ///
  /// In en, this message translates to:
  /// **'Sound from the microphone'**
  String get broadcastAudio;

  /// No description provided for @broadcastCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get broadcastCancel;

  /// No description provided for @broadcastSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get broadcastSave;

  /// No description provided for @broadcastFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not stream: {message}'**
  String broadcastFailed(String message);

  /// No description provided for @broadcastMicDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone not allowed: streaming without sound'**
  String get broadcastMicDenied;

  /// No description provided for @broadcastNotBroadcastMode.
  ///
  /// In en, this message translates to:
  /// **'The camera is not in broadcast mode'**
  String get broadcastNotBroadcastMode;

  /// No description provided for @scoreboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard'**
  String get scoreboardTitle;

  /// No description provided for @scoreboardHalf.
  ///
  /// In en, this message translates to:
  /// **'{period}H'**
  String scoreboardHalf(int period);

  /// No description provided for @scoreboardPlus.
  ///
  /// In en, this message translates to:
  /// **'Add a point to {team}'**
  String scoreboardPlus(String team);

  /// No description provided for @scoreboardMinus.
  ///
  /// In en, this message translates to:
  /// **'Take a point from {team}'**
  String scoreboardMinus(String team);

  /// No description provided for @scoreboardStartClock.
  ///
  /// In en, this message translates to:
  /// **'Start the clock'**
  String get scoreboardStartClock;

  /// No description provided for @scoreboardPauseClock.
  ///
  /// In en, this message translates to:
  /// **'Stop the clock'**
  String get scoreboardPauseClock;

  /// No description provided for @scoreboardSetClock.
  ///
  /// In en, this message translates to:
  /// **'Set the clock'**
  String get scoreboardSetClock;

  /// No description provided for @scoreboardHoldToSetClock.
  ///
  /// In en, this message translates to:
  /// **'Press and hold the clock to set it'**
  String get scoreboardHoldToSetClock;

  /// No description provided for @scoreboardMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get scoreboardMinutes;

  /// No description provided for @scoreboardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Seconds'**
  String get scoreboardSeconds;

  /// No description provided for @scoreboardMore.
  ///
  /// In en, this message translates to:
  /// **'Period, show and settings'**
  String get scoreboardMore;

  /// No description provided for @scoreboardHidden.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard hidden'**
  String get scoreboardHidden;

  /// No description provided for @scoreboardGoToPeriod.
  ///
  /// In en, this message translates to:
  /// **'Go to {period}'**
  String scoreboardGoToPeriod(String period);

  /// No description provided for @scoreboardBackToPeriod.
  ///
  /// In en, this message translates to:
  /// **'Back to {period}'**
  String scoreboardBackToPeriod(String period);

  /// No description provided for @scoreboardPeriodConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to {period}?'**
  String scoreboardPeriodConfirmTitle(String period);

  /// No description provided for @scoreboardPeriodConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The clock stops and goes to {time}.'**
  String scoreboardPeriodConfirmBody(String time);

  /// No description provided for @scoreboardPeriodConfirm.
  ///
  /// In en, this message translates to:
  /// **'Change period'**
  String get scoreboardPeriodConfirm;

  /// No description provided for @scoreboardSize.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard size'**
  String get scoreboardSize;

  /// No description provided for @scoreboardSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get scoreboardSizeSmall;

  /// No description provided for @scoreboardSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get scoreboardSizeMedium;

  /// No description provided for @scoreboardSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get scoreboardSizeLarge;

  /// No description provided for @panelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Panels'**
  String get panelsTitle;

  /// No description provided for @panelLive.
  ///
  /// In en, this message translates to:
  /// **'Live view'**
  String get panelLive;

  /// No description provided for @panelScoreboard.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard'**
  String get panelScoreboard;

  /// No description provided for @panelReplays.
  ///
  /// In en, this message translates to:
  /// **'Replays'**
  String get panelReplays;

  /// No description provided for @panelsNothingShown.
  ///
  /// In en, this message translates to:
  /// **'Everything is hidden. Use the panels button at the top to show the live view, the scoreboard or replays.'**
  String get panelsNothingShown;

  /// No description provided for @cameraScoreboardControls.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard controls'**
  String get cameraScoreboardControls;

  /// No description provided for @cameraConnectViewer.
  ///
  /// In en, this message translates to:
  /// **'Connect a viewer'**
  String get cameraConnectViewer;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomReset.
  ///
  /// In en, this message translates to:
  /// **'Back to 1×'**
  String get zoomReset;

  /// No description provided for @switchRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch role?'**
  String get switchRoleTitle;

  /// No description provided for @switchRoleBroadcastBody.
  ///
  /// In en, this message translates to:
  /// **'The camera is streaming. Switching role ends the stream on YouTube and disconnects every viewer.'**
  String get switchRoleBroadcastBody;

  /// No description provided for @switchRoleViewerBody.
  ///
  /// In en, this message translates to:
  /// **'You are connected to the camera. Switching role closes the live view and this connection.'**
  String get switchRoleViewerBody;

  /// No description provided for @switchRoleViewersBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A viewer is connected. Switching role stops the camera and disconnects it.} other{{count} viewers are connected. Switching role stops the camera and disconnects them.}}'**
  String switchRoleViewersBody(int count);

  /// No description provided for @clipReserveTitle.
  ///
  /// In en, this message translates to:
  /// **'Replay reserve'**
  String get clipReserveTitle;

  /// No description provided for @clipReserveOff.
  ///
  /// In en, this message translates to:
  /// **'Off: the camera deletes each clip once it is on the tablet.'**
  String get clipReserveOff;

  /// No description provided for @clipReserveHint.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The camera keeps the last clip so it can go on air.} other{The camera keeps the last {count} clips so they can go on air.}}'**
  String clipReserveHint(int count);

  /// No description provided for @clipReserveLess.
  ///
  /// In en, this message translates to:
  /// **'Fewer'**
  String get clipReserveLess;

  /// No description provided for @clipReserveMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get clipReserveMore;

  /// No description provided for @clipReserveDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get clipReserveDone;

  /// No description provided for @clipOnCamera.
  ///
  /// In en, this message translates to:
  /// **'On the camera'**
  String get clipOnCamera;

  /// No description provided for @broadcastReplayScoreboard.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard during replays'**
  String get broadcastReplayScoreboard;

  /// No description provided for @broadcastReplayScoreboardHint.
  ///
  /// In en, this message translates to:
  /// **'Off: a replay on air shows only its REPLAY badge.'**
  String get broadcastReplayScoreboardHint;

  /// No description provided for @roleBroadcast.
  ///
  /// In en, this message translates to:
  /// **'Broadcast'**
  String get roleBroadcast;

  /// No description provided for @roleBroadcastEntry.
  ///
  /// In en, this message translates to:
  /// **'Broadcast a match · beta'**
  String get roleBroadcastEntry;

  /// No description provided for @roleBroadcastDescription.
  ///
  /// In en, this message translates to:
  /// **'Streams to YouTube with a scoreboard and replays.'**
  String get roleBroadcastDescription;

  /// No description provided for @checkTitle.
  ///
  /// In en, this message translates to:
  /// **'Before going live'**
  String get checkTitle;

  /// No description provided for @checkKeyOk.
  ///
  /// In en, this message translates to:
  /// **'YouTube stream key saved'**
  String get checkKeyOk;

  /// No description provided for @checkKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'No YouTube stream key yet'**
  String get checkKeyMissing;

  /// No description provided for @checkKeyAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get checkKeyAction;

  /// No description provided for @checkQualityUnknown.
  ///
  /// In en, this message translates to:
  /// **'Quality: the camera is starting'**
  String get checkQualityUnknown;

  /// No description provided for @checkQualityOk.
  ///
  /// In en, this message translates to:
  /// **'Quality {profile}'**
  String checkQualityOk(String profile);

  /// No description provided for @checkQualityLow.
  ///
  /// In en, this message translates to:
  /// **'Quality {profile}: YouTube looks better at 1080p'**
  String checkQualityLow(String profile);

  /// No description provided for @checkQualityAction.
  ///
  /// In en, this message translates to:
  /// **'Use 1080p'**
  String get checkQualityAction;

  /// No description provided for @checkInternetOk.
  ///
  /// In en, this message translates to:
  /// **'Internet reachable'**
  String get checkInternetOk;

  /// No description provided for @checkInternetMissing.
  ///
  /// In en, this message translates to:
  /// **'No Internet: use Wi-Fi with Internet, or share mobile data'**
  String get checkInternetMissing;

  /// No description provided for @checkInternetChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking Internet…'**
  String get checkInternetChecking;

  /// No description provided for @checkPowerOk.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get checkPowerOk;

  /// No description provided for @checkPowerMissing.
  ///
  /// In en, this message translates to:
  /// **'Not charging: plug it in for a whole match'**
  String get checkPowerMissing;

  /// No description provided for @checkMicOk.
  ///
  /// In en, this message translates to:
  /// **'Microphone allowed'**
  String get checkMicOk;

  /// No description provided for @checkMicMissing.
  ///
  /// In en, this message translates to:
  /// **'Microphone not allowed: the stream will be silent'**
  String get checkMicMissing;

  /// No description provided for @checkMicAction.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get checkMicAction;

  /// No description provided for @broadcastMicMute.
  ///
  /// In en, this message translates to:
  /// **'Mute the microphone on air'**
  String get broadcastMicMute;

  /// No description provided for @broadcastMicUnmute.
  ///
  /// In en, this message translates to:
  /// **'Turn the microphone on air on'**
  String get broadcastMicUnmute;

  /// No description provided for @broadcastMicNextStream.
  ///
  /// In en, this message translates to:
  /// **'No microphone permission yet: it will be on air from the next stream'**
  String get broadcastMicNextStream;

  /// No description provided for @scoreboardSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get scoreboardSet;

  /// No description provided for @scoreboardVisible.
  ///
  /// In en, this message translates to:
  /// **'On screen'**
  String get scoreboardVisible;

  /// No description provided for @scoreboardReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get scoreboardReset;

  /// No description provided for @scoreboardResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset the scoreboard?'**
  String get scoreboardResetTitle;

  /// No description provided for @scoreboardResetBody.
  ///
  /// In en, this message translates to:
  /// **'Scores back to 0, first period and the clock reset. Team names and settings stay.'**
  String get scoreboardResetBody;

  /// No description provided for @scoreboardSettings.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard settings'**
  String get scoreboardSettings;

  /// No description provided for @scoreboardHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get scoreboardHome;

  /// No description provided for @scoreboardAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get scoreboardAway;

  /// No description provided for @scoreboardTeamName.
  ///
  /// In en, this message translates to:
  /// **'Name (up to 5 letters)'**
  String get scoreboardTeamName;

  /// No description provided for @scoreboardTeamColor.
  ///
  /// In en, this message translates to:
  /// **'Color of {team}'**
  String scoreboardTeamColor(String team);

  /// No description provided for @scoreboardPeriods.
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get scoreboardPeriods;

  /// No description provided for @scoreboardPeriodMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes per period'**
  String get scoreboardPeriodMinutes;

  /// No description provided for @scoreboardClockDirection.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get scoreboardClockDirection;

  /// No description provided for @scoreboardCountUp.
  ///
  /// In en, this message translates to:
  /// **'Counts up'**
  String get scoreboardCountUp;

  /// No description provided for @scoreboardCountDown.
  ///
  /// In en, this message translates to:
  /// **'Counts down'**
  String get scoreboardCountDown;

  /// Drawn over a replay on the stream (SPEC §12.6); upper case.
  ///
  /// In en, this message translates to:
  /// **'REPLAY'**
  String get replayLabelOnAir;

  /// No description provided for @replayOnAir.
  ///
  /// In en, this message translates to:
  /// **'REPLAY ON AIR'**
  String get replayOnAir;

  /// No description provided for @replayBackToLive.
  ///
  /// In en, this message translates to:
  /// **'Back to live'**
  String get replayBackToLive;

  /// No description provided for @replaySpeed.
  ///
  /// In en, this message translates to:
  /// **'Replay speed'**
  String get replaySpeed;

  /// No description provided for @replayChoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Where to watch the play?'**
  String get replayChoiceTitle;

  /// No description provided for @replayChoiceTablet.
  ///
  /// In en, this message translates to:
  /// **'Only on this tablet'**
  String get replayChoiceTablet;

  /// No description provided for @replayChoiceAir.
  ///
  /// In en, this message translates to:
  /// **'Also on air'**
  String get replayChoiceAir;

  /// No description provided for @replayNotLive.
  ///
  /// In en, this message translates to:
  /// **'The stream is not on'**
  String get replayNotLive;

  /// No description provided for @replayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This clip is no longer on the camera'**
  String get replayUnavailable;

  /// No description provided for @replayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not put the replay on air: {message}'**
  String replayFailed(String message);

  /// No description provided for @broadcastModeKey.
  ///
  /// In en, this message translates to:
  /// **'Stream key'**
  String get broadcastModeKey;

  /// No description provided for @broadcastModeAccount.
  ///
  /// In en, this message translates to:
  /// **'YouTube account'**
  String get broadcastModeAccount;

  /// No description provided for @youtubeAccountHelp.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the channel\'s Google account: the app creates the live (title and visibility), sends the key to the Camera, and the live starts and ends by itself with the stream.'**
  String get youtubeAccountHelp;

  /// No description provided for @youtubeSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get youtubeSignIn;

  /// No description provided for @youtubeSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get youtubeSignOut;

  /// No description provided for @youtubeWillCreate.
  ///
  /// In en, this message translates to:
  /// **'Saving creates a new live on the channel.'**
  String get youtubeWillCreate;

  /// No description provided for @youtubeTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get youtubeTitle;

  /// No description provided for @youtubeDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get youtubeDescription;

  /// No description provided for @youtubePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get youtubePrivacy;

  /// No description provided for @youtubePrivacyPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get youtubePrivacyPublic;

  /// No description provided for @youtubePrivacyUnlisted.
  ///
  /// In en, this message translates to:
  /// **'Unlisted'**
  String get youtubePrivacyUnlisted;

  /// No description provided for @youtubePrivacyPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get youtubePrivacyPrivate;

  /// No description provided for @youtubeDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Match {date}'**
  String youtubeDefaultTitle(String date);

  /// No description provided for @youtubeLifeReady.
  ///
  /// In en, this message translates to:
  /// **'Ready: goes live as soon as the stream arrives'**
  String get youtubeLifeReady;

  /// No description provided for @youtubeLifeStarting.
  ///
  /// In en, this message translates to:
  /// **'YouTube is starting the live'**
  String get youtubeLifeStarting;

  /// No description provided for @youtubeLifeLive.
  ///
  /// In en, this message translates to:
  /// **'Live on YouTube'**
  String get youtubeLifeLive;

  /// No description provided for @youtubeLifeComplete.
  ///
  /// In en, this message translates to:
  /// **'Finished: saving creates a new live'**
  String get youtubeLifeComplete;

  /// No description provided for @youtubeIngestGood.
  ///
  /// In en, this message translates to:
  /// **'YouTube is receiving the stream'**
  String get youtubeIngestGood;

  /// No description provided for @youtubeIngestBad.
  ///
  /// In en, this message translates to:
  /// **'YouTube is receiving the stream with problems'**
  String get youtubeIngestBad;

  /// No description provided for @youtubeIngestNone.
  ///
  /// In en, this message translates to:
  /// **'YouTube is not receiving anything'**
  String get youtubeIngestNone;

  /// No description provided for @youtubeCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get youtubeCopyLink;

  /// No description provided for @youtubeLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get youtubeLinkCopied;

  /// No description provided for @youtubeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get youtubeRefresh;

  /// No description provided for @youtubeNewLive.
  ///
  /// In en, this message translates to:
  /// **'New live'**
  String get youtubeNewLive;

  /// No description provided for @youtubeErrorLiveNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'This channel can\'t go live yet. Enable it in YouTube Studio > Go live (it can take 24 h).'**
  String get youtubeErrorLiveNotEnabled;

  /// No description provided for @youtubeErrorQuota.
  ///
  /// In en, this message translates to:
  /// **'The YouTube API daily quota is used up. Use a stream key for now.'**
  String get youtubeErrorQuota;

  /// No description provided for @youtubeErrorForbidden.
  ///
  /// In en, this message translates to:
  /// **'YouTube refused access. Sign in again.'**
  String get youtubeErrorForbidden;

  /// No description provided for @youtubeErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach YouTube. Check the internet connection.'**
  String get youtubeErrorNetwork;

  /// No description provided for @youtubeErrorSignIn.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign in: {message}'**
  String youtubeErrorSignIn(String message);

  /// No description provided for @youtubeErrorApi.
  ///
  /// In en, this message translates to:
  /// **'YouTube error: {message}'**
  String youtubeErrorApi(String message);

  /// No description provided for @youtubeQr.
  ///
  /// In en, this message translates to:
  /// **'QR'**
  String get youtubeQr;

  /// No description provided for @youtubeQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch the live'**
  String get youtubeQrTitle;

  /// No description provided for @youtubeQrClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get youtubeQrClose;

  /// No description provided for @youtubeNeedSignIn.
  ///
  /// In en, this message translates to:
  /// **'The stream goes to your YouTube account: sign in again in the stream settings, or switch to Stream key.'**
  String get youtubeNeedSignIn;

  /// No description provided for @youtubeShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get youtubeShare;

  /// No description provided for @camWhatYouTubeSees.
  ///
  /// In en, this message translates to:
  /// **'What YouTube sees'**
  String get camWhatYouTubeSees;

  /// No description provided for @camNoSound.
  ///
  /// In en, this message translates to:
  /// **'NO SOUND'**
  String get camNoSound;

  /// No description provided for @camStreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Stream'**
  String get camStreamTitle;

  /// No description provided for @camOnAirYouTube.
  ///
  /// In en, this message translates to:
  /// **'Live on YouTube'**
  String get camOnAirYouTube;

  /// No description provided for @camOnAirFor.
  ///
  /// In en, this message translates to:
  /// **'on air'**
  String get camOnAirFor;

  /// No description provided for @camMbps.
  ///
  /// In en, this message translates to:
  /// **'Mbps'**
  String get camMbps;

  /// No description provided for @camViewersLabel.
  ///
  /// In en, this message translates to:
  /// **'viewers'**
  String get camViewersLabel;

  /// No description provided for @camStopStream.
  ///
  /// In en, this message translates to:
  /// **'Stop streaming'**
  String get camStopStream;

  /// No description provided for @camStopShort.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get camStopShort;

  /// No description provided for @camMicOpen.
  ///
  /// In en, this message translates to:
  /// **'Microphone on'**
  String get camMicOpen;

  /// No description provided for @camMicOpenHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to turn it off'**
  String get camMicOpenHint;

  /// No description provided for @camMicClosed.
  ///
  /// In en, this message translates to:
  /// **'Microphone off'**
  String get camMicClosed;

  /// No description provided for @camMicClosedHint.
  ///
  /// In en, this message translates to:
  /// **'YouTube hears nothing · tap to turn it on'**
  String get camMicClosedHint;

  /// No description provided for @camTileTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get camTileTemperature;

  /// No description provided for @camTileMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get camTileMemory;

  /// No description provided for @camTileViewers.
  ///
  /// In en, this message translates to:
  /// **'Viewers'**
  String get camTileViewers;

  /// No description provided for @camTileOutbox.
  ///
  /// In en, this message translates to:
  /// **'To send'**
  String get camTileOutbox;

  /// No description provided for @camTileCharging.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get camTileCharging;

  /// No description provided for @camConnectViewerSub.
  ///
  /// In en, this message translates to:
  /// **'QR and code · {count, plural, =0{nobody connected} =1{1 connected} other{{count} connected}}'**
  String camConnectViewerSub(int count);

  /// No description provided for @camPairSheetSub.
  ///
  /// In en, this message translates to:
  /// **'Scan it from InstantReplay on the bench tablet or phone'**
  String get camPairSheetSub;

  /// No description provided for @camPairOrCode.
  ///
  /// In en, this message translates to:
  /// **'Or type this code in the viewer'**
  String get camPairOrCode;

  /// No description provided for @camConnectedNow.
  ///
  /// In en, this message translates to:
  /// **'Connected now'**
  String get camConnectedNow;

  /// No description provided for @camClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get camClose;

  /// No description provided for @camShareLive.
  ///
  /// In en, this message translates to:
  /// **'Share the live'**
  String get camShareLive;

  /// No description provided for @camShareLiveSub.
  ///
  /// In en, this message translates to:
  /// **'YouTube link for families'**
  String get camShareLiveSub;

  /// No description provided for @camShareSheetSub.
  ///
  /// In en, this message translates to:
  /// **'Scan it with the phone camera: it opens the live on YouTube'**
  String get camShareSheetSub;

  /// No description provided for @camShareHint.
  ///
  /// In en, this message translates to:
  /// **'“Share…” opens WhatsApp, email and the other apps on the phone.'**
  String get camShareHint;

  /// No description provided for @camShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get camShareAction;

  /// No description provided for @camPrivacyChangeHint.
  ///
  /// In en, this message translates to:
  /// **'Change it in Prepare the stream.'**
  String get camPrivacyChangeHint;

  /// No description provided for @camPrepareStream.
  ///
  /// In en, this message translates to:
  /// **'Prepare the stream'**
  String get camPrepareStream;

  /// No description provided for @camBlackScreen.
  ///
  /// In en, this message translates to:
  /// **'Black screen'**
  String get camBlackScreen;

  /// No description provided for @camScoreboardShort.
  ///
  /// In en, this message translates to:
  /// **'Scoreboard'**
  String get camScoreboardShort;

  /// No description provided for @camReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to go live'**
  String get camReadyTitle;

  /// No description provided for @camReadySub.
  ///
  /// In en, this message translates to:
  /// **'Everything is checked. Go live when you want.'**
  String get camReadySub;

  /// No description provided for @camAmberHint.
  ///
  /// In en, this message translates to:
  /// **'Amber warnings do not stop you from going live.'**
  String get camAmberHint;

  /// No description provided for @camOperatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording · screen off to save battery'**
  String get camOperatingTitle;

  /// No description provided for @camSavedForNext.
  ///
  /// In en, this message translates to:
  /// **'Saved for the next match'**
  String get camSavedForNext;

  /// No description provided for @camTabDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get camTabDestination;

  /// No description provided for @camTabDestinationSub.
  ///
  /// In en, this message translates to:
  /// **'YouTube · account or key'**
  String get camTabDestinationSub;

  /// No description provided for @camTabImage.
  ///
  /// In en, this message translates to:
  /// **'Picture and sound'**
  String get camTabImage;

  /// No description provided for @camTabImageSub.
  ///
  /// In en, this message translates to:
  /// **'Quality and microphone'**
  String get camTabImageSub;

  /// No description provided for @camTabReplays.
  ///
  /// In en, this message translates to:
  /// **'Replays'**
  String get camTabReplays;

  /// No description provided for @camTabReplaysSub.
  ///
  /// In en, this message translates to:
  /// **'How they look on air'**
  String get camTabReplaysSub;

  /// No description provided for @camStepImage.
  ///
  /// In en, this message translates to:
  /// **'Picture'**
  String get camStepImage;

  /// No description provided for @camStepCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get camStepCheck;

  /// No description provided for @camWhereStream.
  ///
  /// In en, this message translates to:
  /// **'Where does it go?'**
  String get camWhereStream;

  /// No description provided for @camQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Picture quality'**
  String get camQualityTitle;

  /// No description provided for @camQualityLow.
  ///
  /// In en, this message translates to:
  /// **'Saver'**
  String get camQualityLow;

  /// No description provided for @camQualityNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get camQualityNormal;

  /// No description provided for @camQualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get camQualityHigh;

  /// No description provided for @camQualityLowSub.
  ///
  /// In en, this message translates to:
  /// **'mobile data'**
  String get camQualityLowSub;

  /// No description provided for @camQualityNormalSub.
  ///
  /// In en, this message translates to:
  /// **'recommended'**
  String get camQualityNormalSub;

  /// No description provided for @camQualityHighSub.
  ///
  /// In en, this message translates to:
  /// **'good Wi-Fi'**
  String get camQualityHighSub;

  /// No description provided for @camQualityPerHour.
  ///
  /// In en, this message translates to:
  /// **'≈ {gigabytes} GB per hour'**
  String camQualityPerHour(String gigabytes);

  /// No description provided for @camQualityAuto.
  ///
  /// In en, this message translates to:
  /// **'If the connection drops, the stream lowers the quality by itself so it does not cut.'**
  String get camQualityAuto;

  /// No description provided for @camFineTune.
  ///
  /// In en, this message translates to:
  /// **'Fine tune'**
  String get camFineTune;

  /// No description provided for @camSoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get camSoundTitle;

  /// No description provided for @camMicTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera microphone'**
  String get camMicTitle;

  /// No description provided for @camMicSub.
  ///
  /// In en, this message translates to:
  /// **'Sound of the venue. You can mute it on air.'**
  String get camMicSub;

  /// No description provided for @camReplaysTitle.
  ///
  /// In en, this message translates to:
  /// **'How replays look'**
  String get camReplaysTitle;

  /// No description provided for @camGoLiveNow.
  ///
  /// In en, this message translates to:
  /// **'Start streaming'**
  String get camGoLiveNow;

  /// No description provided for @camGoLiveLast.
  ///
  /// In en, this message translates to:
  /// **'Go live, like last time'**
  String get camGoLiveLast;

  /// No description provided for @camNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get camNext;

  /// No description provided for @camSummary.
  ///
  /// In en, this message translates to:
  /// **'SUMMARY'**
  String get camSummary;

  /// No description provided for @camSumKey.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get camSumKey;

  /// No description provided for @camSumYouTube.
  ///
  /// In en, this message translates to:
  /// **'YouTube · {privacy}'**
  String camSumYouTube(String privacy);

  /// No description provided for @camSumReplay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get camSumReplay;

  /// No description provided for @camSumScoreboardOn.
  ///
  /// In en, this message translates to:
  /// **'with scoreboard'**
  String get camSumScoreboardOn;

  /// No description provided for @camSumScoreboardOff.
  ///
  /// In en, this message translates to:
  /// **'badge only'**
  String get camSumScoreboardOff;

  /// No description provided for @camYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get camYes;

  /// No description provided for @camNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get camNo;

  /// No description provided for @camWhoCanSee.
  ///
  /// In en, this message translates to:
  /// **'Who can see it'**
  String get camWhoCanSee;

  /// No description provided for @camPrivacyPublicSub.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find it'**
  String get camPrivacyPublicSub;

  /// No description provided for @camPrivacyUnlistedSub.
  ///
  /// In en, this message translates to:
  /// **'Only with the link'**
  String get camPrivacyUnlistedSub;

  /// No description provided for @camPrivacyPrivateSub.
  ///
  /// In en, this message translates to:
  /// **'Only your account'**
  String get camPrivacyPrivateSub;

  /// No description provided for @camBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get camBack;

  /// No description provided for @sbPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Broadcast scoreboard'**
  String get sbPageTitle;

  /// No description provided for @sbStyle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get sbStyle;

  /// No description provided for @sbClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get sbClassic;

  /// No description provided for @sbClassicSub.
  ///
  /// In en, this message translates to:
  /// **'A thin bar. Names up to 5 letters.'**
  String get sbClassicSub;

  /// No description provided for @sbPlate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get sbPlate;

  /// No description provided for @sbPlateSub.
  ///
  /// In en, this message translates to:
  /// **'Two rows. Full names up to 16 letters.'**
  String get sbPlateSub;

  /// No description provided for @sbDefault.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get sbDefault;

  /// No description provided for @sbClassicCut.
  ///
  /// In en, this message translates to:
  /// **'The Classic style cuts names to 5 letters. Plate shows them in full.'**
  String get sbClassicCut;

  /// No description provided for @sbPreview.
  ///
  /// In en, this message translates to:
  /// **'PREVIEW'**
  String get sbPreview;

  /// No description provided for @sbHomeTeam.
  ///
  /// In en, this message translates to:
  /// **'Home team'**
  String get sbHomeTeam;

  /// No description provided for @sbAwayTeam.
  ///
  /// In en, this message translates to:
  /// **'Away team'**
  String get sbAwayTeam;

  /// No description provided for @sbTeamName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sbTeamName;

  /// No description provided for @sbSizeOnScreen.
  ///
  /// In en, this message translates to:
  /// **'Size on screen'**
  String get sbSizeOnScreen;

  /// No description provided for @sbMatch.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get sbMatch;

  /// No description provided for @sbReplayBadge.
  ///
  /// In en, this message translates to:
  /// **'REPLAY'**
  String get sbReplayBadge;

  /// No description provided for @sbClockStart.
  ///
  /// In en, this message translates to:
  /// **'Start clock'**
  String get sbClockStart;

  /// No description provided for @sbClockPause.
  ///
  /// In en, this message translates to:
  /// **'Pause clock'**
  String get sbClockPause;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
