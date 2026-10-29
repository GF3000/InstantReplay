{{flutter_js}}
{{flutter_build_config}}

// The Camera serves this bundle on a LAN with no Internet (SPEC §6), so nothing may be fetched
// from Google's servers:
// - CanvasKit is local because the build uses --no-web-resources-cdn (useLocalCanvasKit).
// - The UI font (Roboto) is a bundled Flutter font asset.
// - Fallback fonts for glyphs Roboto lacks (emoji, CJK, ...) would come from Google Fonts by
//   default; point them at a local path instead. Nothing is shipped there, so such glyphs render
//   as boxes rather than hanging on an unreachable host.
// No service worker: it needs a secure context (the LAN is plain http) and would cache stale
// bundles across app updates.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: "assets/fallback_fonts/",
  },
});
