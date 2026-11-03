# fotos-iphone

[English](README.md) · **Español**

Herramienta para macOS que copia por **USB** las fotos y vídeos **originales** del iPhone al Mac
(HEIC, DNG, MOV… sin conversión y con todos sus metadatos), usando `ImageCaptureCore`.

> **Estado:** v0.3. Una **app de Mac** (SwiftUI) y una herramienta de **Terminal** sobre la misma biblioteca.

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

- Mac con macOS 14 o posterior y las herramientas de desarrollo de Xcode.
- En el iPhone: *Ajustes → Apps → Fotos → Transferir a Mac o PC → **Conservar originales***.
- Al copiar o simular: iPhone desbloqueado y conectado por cable, con el bloqueo automático en *Nunca*;
  **Captura de Imagen abierta** y Fotos cerrada en el Mac.

## Compilar y probar

```bash
./compilar.sh     # deja ./fotos-iphone y sus traducciones; errores en compilacion.log
./probar.sh       # pruebas que no necesitan iPhone; salida en pruebas.log
./empaquetar-app.sh && open "Fotos iPhone.app"   # la app de Mac; errores en compilacion-app.log
```

## App de Mac

`./empaquetar-app.sh` monta **Fotos iPhone.app** en la carpeta del proyecto (puedes moverla a
Aplicaciones). Usa las mismas opciones, perfiles y cachés que la herramienta de Terminal.

1. **Al abrirla** comprueba que Captura de Imagen está abierta y, si no, la abre (sin ella macOS no
   entrega las fotos del iPhone). Si el catálogo no llega, avisa de qué hacer. Mientras conecta,
   **Detener** corta el intento y **Reconectar** lo repite.
2. **Opciones** (panel izquierdo): perfil, periodo (incluido *el mes pasado*), orígenes, cámaras
   (*este iPhone*, deducido de sus fotos recientes; cualquiera; o elegidas), versiones, vídeos, RAW,
   organización y destino. Los perfiles se guardan, se actualizan (lo confirma) y se borran
   (salvo los integrados).
3. **Simular** muestra qué se copiaría, qué ya está copiado y qué se descarta y por qué, con
   miniaturas pedidas al iPhone (sin descargar los archivos). Al pulsar una se ve cada archivo.
4. **Copiar…** solo se activa tras una simulación al día, y pide confirmación. Muestra progreso,
   velocidad y tiempo restante; se puede **pausar**, **reanudar** y **cancelar** (al terminar el
   archivo en curso). El Mac no se duerme durante la copia.
5. **Borrar del iPhone** (selector de arriba): lo del periodo que esté en la carpeta de destino o
   lo que copió una copia anterior (su `informe.csv`). Primero se **revisa** qué se borraría y,
   para borrar, hay que escribir la clave («BORRAR 12»). Cada borrado se comprueba en el iPhone.
6. Cerrar la ventana es salir. Con una copia o un borrado en curso, pide confirmación.
7. **Ajustes** (⌘,): idioma de la app (el del sistema, español o inglés).

## Terminal

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
| Viaje | Las fotos y vídeos de la cámara de este iPhone (como la v0.1) en el rango de fechas que indiques |

Se guardan en `~/Library/Application Support/fotos-iphone/perfiles/`. Guardar con un nombre que ya existe lo actualiza (y lo confirma). Los integrados no se pueden borrar; si actualizas uno, borrar tu versión lo devuelve al original.

«Este iPhone» es la cámara por defecto: el iPhone no dice su modelo por cable, así que se deduce de sus fotos recientes (las de la Cámara llevan el modelo en sus metadatos).

```bash
./fotos-iphone --perfiles                                   # ver los disponibles
./fotos-iphone --perfil "Respaldo completo" --destino ~/Pictures/iPhone
./fotos-iphone --perfil Viaje --desde 2026-10-01 --hasta 2026-10-15 --destino ~/Pictures/Viaje
./fotos-iphone --origenes capturas --organizar mes --guardar-perfil "Capturas"
./fotos-iphone --borrar-perfil "Capturas"
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

# Todo lo del mes pasado (el mes natural anterior completo)
./fotos-iphone --mes-pasado --destino ~/Pictures/Mes --simular

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

> **Borrar del iPhone (`--borrar`).** El borrado por cable es definitivo (no pasa por
> «Eliminados recientemente») y, con Fotos de iCloud, también borra en iCloud. Solo toca los
> elementos cuyo original y edición están en el respaldo, pide escribir una clave y comprueba
> después en el iPhone que cada foto se borró de verdad. Con `--informe informe.csv` los candidatos
> salen del informe de una copia:
>
> ```bash
> ./fotos-iphone --borrar --simular --informe ~/Pictures/Respaldo/informe.csv
> ```

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
Sources/FotosIPhoneApp/   App de Mac (SwiftUI)
App/                      Info.plist, icono (AppIcon.icns) y su generador (generar-icono.py)
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

- **v0.2** ✓: biblioteca Swift separada, filtros configurables, idiomas, asistente de preguntas,
  perfiles y borrado comprobado.
- **v0.3** ✓: app de Mac en SwiftUI sobre la misma biblioteca: estado del iPhone, opciones y perfiles,
  vista previa de la simulación con miniaturas, copia con pausa y reanudación, borrado desde la carpeta
  o desde un `informe.csv`, idioma en Ajustes e icono.
