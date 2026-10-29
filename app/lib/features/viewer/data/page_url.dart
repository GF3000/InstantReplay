import 'page_url_io.dart' if (dart.library.js_interop) 'page_url_web.dart' as platform;

/// Removes the `?k=` token from the browser address bar so it is not bookmarked or shared.
/// No-op outside the web.
void stripTokenFromPageUrl() => platform.stripTokenFromPageUrl();
