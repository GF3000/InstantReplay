# InstantReplay

[![CI](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml/badge.svg)](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml)

*[Read in English](README.md)*

Repeticiones instantáneas para deportes de equipo, sin conexión a Internet. Un móvil Android en un trípode graba de forma continua y guarda el último minuto en un búfer circular. Desde el móvil o la tablet del entrenador se ve el directo y, con un toque, se recuperan los últimos 10–60 segundos para revisarlos a cámara lenta, etiquetarlos y compartirlos. Todo funciona en una red Wi-Fi local (hotspot de un móvil o router de viaje).

> **Estado:** fase de diseño. La arquitectura y los requisitos están en [docs/SPEC.md](docs/SPEC.md), en inglés. La Fase 0 (prueba de concepto de la captura nativa) está en marcha.

## Cómo funciona

- **Rol Cámara** (Android): graba en 1080p H.264 dentro de un búfer circular de ~80 s, dividido en fragmentos fMP4 de 1 segundo. Emite un directo de baja latencia por WebRTC y sirve los clips por HTTP. Los clips se generan concatenando fragmentos, sin recodificar y sin FFmpeg.
- **Rol Visor** (Android): directo, un botón grande de *Guardar* con duraciones predefinidas, reproductor de análisis (0,25×/0,5×/1× y fotograma a fotograma), sesiones, etiquetas de un toque, exportación a la galería y botón de compartir del sistema.
- **Visor web** (cualquier navegador, servido por la Cámara): directo, guardar, revisar y descargar los clips de la sesión en curso.

## Licencia

[Apache-2.0](LICENSE)
