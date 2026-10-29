/// The web Viewer bundle shipped inside the APK, which the Camera serves to browsers (SPEC §6).
///
/// Returns the directory holding `index.html`, or null when this build has no bundle
/// (e.g. a plain `flutter build apk` without the web step).
///
/// Placeholder until the bundle pipeline lands (S1); always null.
Future<String?> extractWebBundle() async => null;
