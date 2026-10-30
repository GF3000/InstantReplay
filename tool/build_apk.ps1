<#
.SYNOPSIS
  Builds the Android APK with the offline web Viewer bundle inside it (SPEC §6, PLAN 5.1).

.DESCRIPTION
  1. flutter build web --release --no-web-resources-cdn: CanvasKit and the other engine
     resources are copied into build/web instead of being loaded from Google's CDN, because
     the Camera has no Internet and browsers fetch everything from it.
  2. Check the bundle references no external host (see the check below).
  3. Copy app/build/web to app/android/app/src/main/assets/web_viewer/ (Android native
     assets, git-ignored), minus debug symbols. Not Flutter assets: the web build would then
     contain the previous bundle recursively.
  4. flutter build apk. MainActivity extracts the bundle to filesDir at runtime.

.EXAMPLE
  tool/build_apk.ps1            # debug APK
  tool/build_apk.ps1 -Release   # release APK
  tool/build_apk.ps1 -Release -SplitPerAbi   # one release APK per CPU architecture
#>
param(
  [switch]$Release,
  # arm64 alone is less than half the size of the universal APK.
  [switch]$SplitPerAbi
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
  param([string]$Exe, [string[]]$Arguments)
  Write-Host "==> $Exe $($Arguments -join ' ')"
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'app'
$webOut = Join-Path $appDir 'build/web'
$assetsDir = Join-Path $appDir 'android/app/src/main/assets/web_viewer'

Push-Location $appDir
try {
  Invoke-Checked flutter @('build', 'web', '--release', '--no-web-resources-cdn')

  # The bundle must not reach out to the Internet. Two Google URLs are compiled in as defaults
  # and are neutralized, so they are removed before the search:
  # - www.gstatic.com/flutter-canvaskit in flutter.js: only used when useLocalCanvasKit is false.
  # - fonts.gstatic.com/s/ in main.dart.js: default fontFallbackBaseUrl, overridden in
  #   web/flutter_bootstrap.js.
  Write-Host '==> Checking the web bundle for external hosts'
  $external = 'gstatic\.com|googleapis\.com|fonts\.google|unpkg\.com|jsdelivr\.net'
  $neutralized = 'https://www\.gstatic\.com/flutter-canvaskit|https://fonts\.gstatic\.com/s/'
  $bootstrap = [IO.File]::ReadAllText((Join-Path $webOut 'flutter_bootstrap.js'))
  if (-not $bootstrap.Contains('"useLocalCanvasKit":true')) { throw 'flutter_bootstrap.js does not use local CanvasKit.' }
  if (-not $bootstrap.Contains('fontFallbackBaseUrl')) { throw 'flutter_bootstrap.js does not override fontFallbackBaseUrl.' }
  $hits = @()
  foreach ($file in Get-ChildItem -Path $webOut -Recurse -File | Where-Object Extension -ne '.symbols') {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::GetEncoding(28591)) -replace $neutralized, ''
    foreach ($m in [regex]::Matches($text, ".{0,60}($external).{0,60}")) { $hits += "$($file.Name): $($m.Value)" }
  }
  if ($hits) {
    $hits | ForEach-Object { Write-Host "  $_" }
    throw 'The web bundle references an external host (see above).'
  }
  Write-Host '    clean'

  Write-Host "==> Copying $webOut -> $assetsDir"
  if (Test-Path $assetsDir) { Remove-Item -Recurse -Force $assetsDir }
  New-Item -ItemType Directory -Force $assetsDir | Out-Null
  Copy-Item -Path (Join-Path $webOut '*') -Destination $assetsDir -Recurse
  # CanvasKit debug symbols (~9 MB) are only useful to engine developers.
  Get-ChildItem -Path $assetsDir -Recurse -File -Filter '*.symbols' | Remove-Item -Force

  $mode = if ($Release) { '--release' } else { '--debug' }
  $buildArgs = @('build', 'apk', $mode)
  if ($SplitPerAbi) { $buildArgs += '--split-per-abi' }
  Invoke-Checked flutter $buildArgs
}
finally {
  Pop-Location
}
