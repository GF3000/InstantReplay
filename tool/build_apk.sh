#!/usr/bin/env bash
# Builds the Android APK with the offline web Viewer bundle inside it (SPEC §6, PLAN 5.1).
#
#   tool/build_apk.sh            # debug APK
#   tool/build_apk.sh --release  # release APK
#   tool/build_apk.sh --release --split-per-abi  # one release APK per CPU architecture
#
# 1. `flutter build web --release --no-web-resources-cdn`: CanvasKit and the other engine
#    resources are copied into build/web instead of being loaded from Google's CDN, because
#    the Camera has no Internet and browsers fetch everything from it.
# 2. Check the bundle references no external host (see check below).
# 3. Copy app/build/web to app/android/app/src/main/assets/web_viewer/ (Android native
#    assets, git-ignored), minus debug symbols. Not Flutter assets: the web build would then
#    contain the previous bundle recursively.
# 4. `flutter build apk`. MainActivity extracts the bundle to filesDir at runtime.
set -euo pipefail

mode="--debug"
split=()
for arg in "$@"; do
  case "$arg" in
    --release) mode="--release" ;;
    --debug) mode="--debug" ;;
    # One APK per CPU architecture (release only): arm64 alone is less than half the size.
    --split-per-abi) split=(--split-per-abi) ;;
    *) echo "Unknown argument: $arg (expected --debug, --release or --split-per-abi)" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/app"
web_out="$app_dir/build/web"
assets_dir="$app_dir/android/app/src/main/assets/web_viewer"

cd "$app_dir"

echo "==> flutter build web --release --no-web-resources-cdn"
flutter build web --release --no-web-resources-cdn

# The bundle must not reach out to the Internet. Two Google URLs are compiled in as defaults and
# are neutralized, so they are removed before the search:
# - www.gstatic.com/flutter-canvaskit in flutter.js: only used when useLocalCanvasKit is false.
# - fonts.gstatic.com/s/ in main.dart.js: default fontFallbackBaseUrl, overridden in
#   web/flutter_bootstrap.js.
echo "==> Checking the web bundle for external hosts"
external='gstatic\.com|googleapis\.com|fonts\.google|unpkg\.com|jsdelivr\.net'
neutralized='https://www\.gstatic\.com/flutter-canvaskit|https://fonts\.gstatic\.com/s/'
grep -q '"useLocalCanvasKit":true' "$web_out/flutter_bootstrap.js" \
  || { echo "ERROR: flutter_bootstrap.js does not use local CanvasKit." >&2; exit 1; }
grep -q 'fontFallbackBaseUrl' "$web_out/flutter_bootstrap.js" \
  || { echo "ERROR: flutter_bootstrap.js does not override fontFallbackBaseUrl." >&2; exit 1; }
hits="$(find "$web_out" -type f ! -name '*.symbols' -print0 \
  | xargs -0 sed -E "s#${neutralized}##g" | grep -aoE ".{0,60}(${external}).{0,60}" || true)"
if [ -n "$hits" ]; then
  echo "$hits" >&2
  echo "ERROR: the web bundle references an external host." >&2
  exit 1
fi
echo "    clean"

echo "==> Copying $web_out -> $assets_dir"
rm -rf "$assets_dir"
mkdir -p "$assets_dir"
cp -R "$web_out/." "$assets_dir/"
# CanvasKit debug symbols (~9 MB) are only useful to engine developers.
find "$assets_dir" -name '*.symbols' -delete

echo "==> flutter build apk $mode ${split[*]:-}"
flutter build apk "$mode" "${split[@]}"
