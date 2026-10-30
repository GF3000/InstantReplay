# Branding

App icon and splash screen, concept "Bucle": a replay arrow around a ball, ink on amber (`#FFC107`, the theme's seed colour).

`render.mjs` holds the glyph and writes the SVG sources here and the PNGs in `png/`:

| File | Used for |
|---|---|
| `icon_foreground` | Android adaptive icon, foreground layer (full 108 dp canvas; background is the colour `#FFC107`) |
| `icon_monochrome` | Android 13+ themed icon |
| `icon_legacy` | Fallback `mipmap/ic_launcher.png`, web `Icon-192/512.png` and `favicon.png` |
| `icon_maskable` | Web `Icon-maskable-192/512.png` (full bleed) |
| `splash_android12` | Android 12+ splash icon, on an amber icon background |
| `splash_legacy` | Android 10–11 splash image |

The splash is black in light and dark mode because the app is always dark.

## Regenerate

From `app/branding` (resvg needs Node; it is not a project dependency):

```bash
npm i --no-save @resvg/resvg-js@2.6.2 && node render.mjs
```

Then from `app/`:

```bash
dart run flutter_launcher_icons && dart run flutter_native_splash:create
```

The web icons are resized by hand from `png/icon_legacy.png` (favicon 32 px, `Icon-192/512`) and `png/icon_maskable.png` (`Icon-maskable-192/512`).
