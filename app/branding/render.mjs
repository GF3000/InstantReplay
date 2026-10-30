// Renders the branding PNGs from the glyph below (concept "Bucle": replay loop around a ball).
// Usage, from app/branding: npm i --no-save @resvg/resvg-js@2.6.2 && node render.mjs
// Then, from app/: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import { writeFileSync, mkdirSync } from 'node:fs';
import { Resvg } from '@resvg/resvg-js';

const AMBER = '#FFC107', INK = '#15120A';
// 108 x 108 adaptive-icon canvas: visible area is the central 72 x 72, safe zone a 66-diameter circle.
const glyph = (ink, seam) => `
  <path d="M34.95 43A22 22 0 1 0 54 32" fill="none" stroke="${ink}" stroke-width="7"/>
  <path d="M42.8 32L56.45 22.55L56.45 41.45Z" fill="${ink}" stroke="${ink}" stroke-width="1.5" stroke-linejoin="round"/>
  <circle cx="54" cy="54" r="10" fill="${ink}"/>
  ${seam ? `<g fill="none" stroke="${seam}" stroke-width="1.8" stroke-linecap="round">
    <path d="M54 44.5V63.5"/><path d="M47 47.5Q51.5 54 47 60.5"/><path d="M61 47.5Q56.5 54 61 60.5"/></g>` : ''}`;
const squircle = 'M54 18C80 18 90 28 90 54C90 80 80 90 54 90C28 90 18 80 18 54C18 28 28 18 54 18Z';
const svg = (viewBox, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">${body}</svg>`;

const files = {
  // Android adaptive icon layers (background is the colour #FFC107).
  icon_foreground: [svg('0 0 108 108', glyph(INK, AMBER)), 1024],
  icon_monochrome: [svg('0 0 108 108', glyph('#FFFFFF')), 1024],
  // Legacy mipmap and web icons: the visible 72 x 72 area, squircle-shaped.
  icon_legacy: [svg('18 18 72 72', `<path d="${squircle}" fill="${AMBER}"/>${glyph(INK, AMBER)}`), 1024],
  // Web maskable icon: full bleed, the glyph already sits inside the 80 % safe circle.
  icon_maskable: [svg('0 0 108 108', `<rect width="108" height="108" fill="${AMBER}"/>${glyph(INK, AMBER)}`), 1024],
  // Splash, Android 12+: 288 dp canvas whose central 192 dp circle shows; the icon background colour is amber.
  splash_android12: [svg('0 0 108 108', glyph(INK, AMBER)), 960],
  // Splash, Android 10-11 and web: the round icon itself, at 4x for a 160 dp image.
  splash_legacy: [svg('18 18 72 72', `<circle cx="54" cy="54" r="36" fill="${AMBER}"/>${glyph(INK, AMBER)}`), 640],
};

mkdirSync('png', { recursive: true });
for (const [name, [source, size]] of Object.entries(files)) {
  writeFileSync(`${name}.svg`, source);
  writeFileSync(`png/${name}.png`, new Resvg(source, { fitTo: { mode: 'width', value: size } }).render().asPng());
}
