import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('instant_replay/web_bundle');

/// The web Viewer bundle shipped inside the APK, which the Camera serves to browsers (SPEC §6).
///
/// Returns the directory holding `index.html`, or null when this build has no bundle
/// (e.g. a plain `flutter build apk` without `tool/build_apk`), on web, or if the native side
/// fails. The native side copies the APK's `assets/web_viewer/` to `<filesDir>/web_viewer/` only
/// when the APK changed since the last copy, off the main thread.
Future<String?> extractWebBundle() async {
  if (kIsWeb) return null;
  try {
    return await _channel.invokeMethod<String>('extract');
  } on PlatformException catch (e) {
    debugPrint('extractWebBundle failed: ${e.code} ${e.message}');
    return null;
  } on MissingPluginException {
    return null;
  }
}
