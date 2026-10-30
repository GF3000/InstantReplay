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

  /// No description provided for @viewerReviewNextFrame.
  ///
  /// In en, this message translates to:
  /// **'Next frame'**
  String get viewerReviewNextFrame;

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

  /// No description provided for @libraryTemplateLabelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags and categories'**
  String get libraryTemplateLabelsTitle;

  /// No description provided for @libraryCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get libraryCategoriesTitle;

  /// No description provided for @libraryCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get libraryCategory;

  /// No description provided for @libraryCategoryAdd.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get libraryCategoryAdd;

  /// No description provided for @libraryCategoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No categories. Add one to group your clips.'**
  String get libraryCategoriesEmpty;

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

  /// No description provided for @libraryCategoryAttack.
  ///
  /// In en, this message translates to:
  /// **'Attack'**
  String get libraryCategoryAttack;

  /// No description provided for @libraryCategoryDefense.
  ///
  /// In en, this message translates to:
  /// **'Defence'**
  String get libraryCategoryDefense;

  /// No description provided for @libraryCategoryTransition.
  ///
  /// In en, this message translates to:
  /// **'Transition'**
  String get libraryCategoryTransition;

  /// No description provided for @libraryCategorySetPiece.
  ///
  /// In en, this message translates to:
  /// **'Set piece'**
  String get libraryCategorySetPiece;

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
