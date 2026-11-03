# fotos-iphone

[English](README.md) · **Español**

Herramienta para macOS que copia por **USB** las fotos y vídeos **originales** del iPhone al Mac
(HEIC, DNG, MOV… sin conversión y con todos sus metadatos), usando `ImageCaptureCore`.

> **Estado:** v0.2 en desarrollo. Funciona desde Terminal. La v0.3 añadirá una app de Mac (SwiftUI).

## Qué hace

- Copia los archivos tal como están en el iPhone, sin convertir HEIC a JPG ni recomprimir vídeos.
- Agrupa cada foto con todo lo que cuelga de ella: versión editada (`IMG_E…`), instrucciones de
  edición (`.AAE`) y vídeo de la Live Photo.
- Clasifica cada elemento por su **origen**: cámara (por modelo), captura de pantalla, grabación
  de pantalla u otras apps (WhatsApp, Telegram, descargas…).
- Decide qué copiar según **opciones**: periodo, versiones (solo originales / versión final /
  original + editada), `.AAE`, vídeos (con tamaño máximo), vídeos de Live Photos, RAW, orígenes y
  cámaras, y organización del destino (carpeta única, por año y mes, o por día).
- **Simula** antes de copiar: muestra qué se copiaría y qué se descartaría, y por qué.
- Lee la cámara de los vídeos leyendo solo su cabecera (unos KB), sin descargarlos.
- Copia de forma segura: descarga a una carpeta temporal, comprueba el tamaño y luego mueve al destino.
  Se puede interrumpir y reanudar (lo ya copiado se salta). Genera un `informe.csv` y un manifiesto
  (`.fotos-iphone/manifiesto.json` en el destino) con dónde quedó cada archivo.
- Mensajes en **español e inglés** (preparado para añadir más idiomas).

## Requisitos

- Mac con macOS 13 o posterior y las herramientas de desarrollo de Xcode.
- En el iPhone: *Ajustes → Apps → Fotos → Transferir a Mac o PC → **Conservar originales***.
- Al copiar o simular: iPhone desbloqueado y conectado por cable, con el bloqueo automático en *Nunca*;
  **Captura de Imagen abierta** y Fotos cerrada en el Mac.

## Compilar y probar

```bash
./compilar.sh     # deja ./fotos-iphone y sus traducciones; errores en compilacion.log
./probar.sh       # pruebas que no necesitan iPhone; salida en pruebas.log
```

## Uso

### Asistente

Sin opciones, la herramienta pregunta paso a paso qué copiar (periodo, orígenes, cámaras detectadas
en el iPhone, versiones, vídeos, RAW, organización y destino), con lo elegido la última vez como
respuesta por defecto. Al final simula, muestra qué se copiaría, qué se descarta y por qué, y si cabe
en el disco, y **pide confirmación antes de copiar**. Las opciones se pueden guardar como perfil.

```bash
./fotos-iphone
```

### Perfiles

Vienen tres integrados y puedes guardar los tuyos:

| Perfil | Qué copia |
|---|---|
| Respaldo completo | Todo el carrete, de cualquier origen y cámara, original + editada, con vídeos de Live Photos, por año y mes |
| Respaldo últimos días | Los últimos 7 días, de cualquier cámara, versión final, por día |
| Viaje | Las fotos y vídeos del iPhone 17 Pro (como la v0.1) en el rango de fechas que indiques |

Se guardan en `~/Library/Application Support/fotos-iphone/perfiles/`.

```bash
./fotos-iphone --perfiles                                   # ver los disponibles
./fotos-iphone --perfil "Respaldo completo" --destino ~/Pictures/iPhone
./fotos-iphone --perfil Viaje --desde 2026-10-01 --hasta 2026-10-15 --destino ~/Pictures/Viaje
./fotos-iphone --origenes capturas --organizar mes --guardar-perfil "Capturas"
```

### Con opciones

Una copia real siempre simula primero y pregunta; `--si` copia sin preguntar.

```bash
# Simulación detallada
./fotos-iphone --desde 2026-10-01 --hasta 2026-10-31 --simular

# Copia real
./fotos-iphone --desde 2026-10-01 --hasta 2026-10-31 --destino ~/Pictures/Respaldo-iPhone

# Capturas y archivos de otras apps de la última semana, organizados por meses
./fotos-iphone --dias 7 --origenes capturas,apps --organizar mes --simular

# Todo el carrete, cualquier cámara, solo la versión final, vídeos de hasta 2 GB
./fotos-iphone --todo --origenes todo --cualquier-camara --versiones final --video-max 2GB --simular

# ¿Qué cámaras y orígenes hay en el iPhone?
./fotos-iphone --camaras

# Ver cómo reconoce el Mac los últimos elementos (origen, cámara, grupos…)
./fotos-iphone --inspeccionar --ultimos 20

./fotos-iphone --ayuda
```

Todas las opciones se aceptan en español y en inglés (`--desde` = `--from`, `--destino` = `--dest`…).
`--idioma en` o `--language es` fuerzan el idioma de los mensajes.

> **Borrar del iPhone (`--borrar`) es experimental.** El borrado por cable es definitivo
> (no pasa por «Eliminados recientemente») y, con Fotos de iCloud, también borra en iCloud.
> Pide confirmación escrita y solo toca lo que está completo en el respaldo.

## Cómo reconoce el origen de cada archivo

| Origen | Cómo se reconoce |
|---|---|
| Cámara | Nombre `IMG_…` con fabricante y modelo en los metadatos |
| Captura de pantalla | `IMG_….PNG`, o metadatos marcados «Screenshot» |
| Grabación de pantalla | Vídeo sin cámara con la resolución exacta de una pantalla de iPhone |
| Otras apps | Nombre aleatorio (`THQV8599.JPG`, `URMW5828.MP4`…) o imagen sin datos de cámara |

Solo se puede copiar lo que está físicamente en el iPhone: con «Optimizar almacenamiento»,
los originales que solo están en iCloud no se ven por cable.

## Estructura

```
Sources/FotosCore/        Lógica pura (sin iPhone): catálogo, opciones, reglas, informe, idiomas
  Resources/<idioma>.lproj/Localizable.strings
Sources/FotosIPhoneKit/   Conexión con el iPhone, copia y borrado (ImageCaptureCore, AVFoundation)
Sources/fotos-iphone/     Herramienta de Terminal
Tests/FotosCoreTests/     Pruebas
```

## Añadir un idioma

Copia `Sources/FotosCore/Resources/en.lproj` con el código del idioma (por ejemplo `fr.lproj`),
traduce los valores (la parte derecha de cada línea, respetando `%@`, `%ld` y `\n`) y recompila.
`./probar.sh` avisa si falta algún texto.

## Privacidad

El repositorio no contiene datos personales: los informes `.csv`, las listas `.txt`, los logs,
los manifiestos de copia y cualquier foto o vídeo están excluidos en `.gitignore`.
Los perfiles y cachés se guardan fuera del proyecto, en `~/Library/Application Support/fotos-iphone/`.

## Hoja de ruta

- **v0.2** (en curso): biblioteca Swift separada ✓, filtros configurables ✓, idiomas ✓,
  asistente de preguntas ✓, perfiles ✓. Falta: probar el borrado con fotos de prueba.
- **v0.3**: app de Mac en SwiftUI sobre la misma biblioteca: estado del iPhone, calendario y opciones,
  vista previa de la simulación con miniaturas, copia con pausa y reanudación, y pantalla de borrado aparte.
