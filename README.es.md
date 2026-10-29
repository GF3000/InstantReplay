# InstantReplay

[![CI](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml/badge.svg)](https://github.com/GF3000/InstantReplay/actions/workflows/ci.yml)

*[Read in English](README.md)*

Repeticiones instantáneas para deportes de equipo, sin conexión a Internet. Un móvil Android en un trípode graba de forma continua y guarda el último minuto en un búfer circular. Desde el móvil o la tablet del entrenador se ve el directo y, con un toque, se recuperan los últimos 10–60 segundos para revisarlos a cámara lenta, etiquetarlos y compartirlos. Todo funciona en una red Wi-Fi local (hotspot de un móvil o router de viaje).

> **Estado:** primeras versiones, ya funciona de punta a punta: la Cámara graba y sirve el directo y los clips, y cualquier navegador en la misma Wi-Fi hace de Visor (directo, guardar, etiquetar, revisar). Lo siguiente es probarlo en entrenamientos reales. Diseño (en inglés): [docs/SPEC.md](docs/SPEC.md) · UX: [docs/UX.md](docs/UX.md) · Plan: [docs/PLAN-v0.1.md](docs/PLAN-v0.1.md).
>
> **Probarlo:** instala el APK en un móvil Android (10 o superior) y sigue la [guía de montaje](docs/guia-de-montaje.md).

## Cómo funciona

- **Rol Cámara** (Android): graba en 1080p H.264 dentro de un búfer circular de ~80 s, dividido en fragmentos fMP4 de 1 segundo. Emite un directo de baja latencia por WebRTC y sirve los clips por HTTP. Los clips se generan concatenando fragmentos, sin recodificar y sin FFmpeg.
- **Visor web** (cualquier navegador en la misma Wi-Fi, servido por la Cámara; se entra escaneando su QR): directo, botón grande de *Guardar* (20 s, o 10/30/60), etiquetas de un toque justo después de guardar, lista de clips con miniaturas y filtros, y reproductor (bucle, 0,25×/0,5×/1×, fotograma a fotograma, descarga). Los clips se guardan en la pestaña del navegador durante la sesión.
- **Visor nativo** (Android, previsto): lo mismo más biblioteca permanente, exportación a la galería y botón de compartir del sistema.

## Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés) para las herramientas, los comandos de compilación y pruebas y el flujo de PR, y [docs/dev-setup.md](docs/dev-setup.md) para depurar en el móvil por Wi-Fi.

## Licencia

[Apache-2.0](LICENSE)
