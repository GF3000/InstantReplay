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

  /// No description provided for @viewerComingSoon.
  ///
  /// In en, this message translates to:
  /// **'The Viewer screen arrives in M4.'**
  String get viewerComingSoon;

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
