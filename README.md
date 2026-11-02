# fotos-iphone

**English** · [Español](README.es.md)

A macOS tool that copies the **original** photos and videos from an iPhone to a Mac over **USB**
(HEIC, DNG, MOV… with no conversion and all their metadata), using `ImageCaptureCore`.

> **Status:** v0.2 in development. Works from Terminal. v0.3 will add a Mac app (SwiftUI).

## What it does

- Copies files exactly as they are on the iPhone: no HEIC-to-JPG conversion, no video re-encoding.
- Groups each photo with everything that belongs to it: edited version (`IMG_E…`), edit
  instructions (`.AAE`) and the Live Photo video.
- Classifies each item by **source**: camera (by model), screenshot, screen recording or other
  apps (WhatsApp, Telegram, downloads…).
- Decides what to copy based on **options**: period, versions (originals only / final version /
  original + edited), `.AAE`, videos (with a maximum size), Live Photo videos, RAW, sources and
  cameras, and destination layout (single folder, by year and month, or by day).
- **Simulates** before copying: shows what would be copied, what would be skipped, and why.
- Copies safely: downloads to a temporary folder, checks the size, then moves it into place.
  It can be interrupted and resumed (what was already copied is skipped). Writes an `informe.csv` report.
- Messages in **English and Spanish** (ready for more languages).

## Requirements

- A Mac with macOS 13 or later and the Xcode developer tools.
- On the iPhone: *Settings → Apps → Photos → Transfer to Mac or PC → **Keep Originals***.
- When copying or simulating: iPhone unlocked and connected by cable, with Auto-Lock set to *Never*;
  **Image Capture open** and Photos closed on the Mac.

## Build and test

```bash
./compilar.sh     # builds ./fotos-iphone and its translations; errors go to compilacion.log
./probar.sh       # tests that don't need an iPhone; output in pruebas.log
```

## Usage

```bash
# Always simulate first
./fotos-iphone --from 2026-10-01 --to 2026-10-31 --simulate

# Real copy
./fotos-iphone --from 2026-10-01 --to 2026-10-31 --dest ~/Pictures/iPhone-Backup

# See how the Mac recognizes the latest items (source, camera, groups…)
./fotos-iphone --inspect --last 20

./fotos-iphone --help
```

Every option is accepted in English and Spanish (`--from` = `--desde`, `--dest` = `--destino`…).
`--language en` or `--idioma es` force the language of the messages (default: the system's).

> **Deleting from the iPhone (`--delete`) is experimental.** Deleting over the cable is permanent
> (it does not go to “Recently Deleted”) and, with iCloud Photos, it also deletes from iCloud.
> It asks for typed confirmation and only touches items that are fully backed up.

## How the source of each file is recognized

| Source | How it is recognized |
|---|---|
| Camera | `IMG_…` name with make and model in the metadata |
| Screenshot | `IMG_….PNG`, or metadata marked “Screenshot” |
| Screen recording | Video without camera data at the exact resolution of an iPhone screen |
| Other apps | Random name (`THQV8599.JPG`, `URMW5828.MP4`…) or image without camera data |

Only what is physically on the iPhone can be copied: with “Optimize Storage”, originals that
are only in iCloud are not visible over the cable.

## Layout

```
Sources/FotosCore/        Pure logic (no iPhone): catalog, options, rules, report, languages
  Resources/<language>.lproj/Localizable.strings
Sources/FotosIPhoneKit/   iPhone connection, copy and delete (ImageCaptureCore, AVFoundation)
Sources/fotos-iphone/     Terminal tool
Tests/FotosCoreTests/     Tests
```

The code (identifiers and comments) is written in Spanish.

## Adding a language

Copy `Sources/FotosCore/Resources/en.lproj` using the language code (for example `fr.lproj`),
translate the values (the right-hand side of each line, keeping `%@`, `%ld` and `\n`) and rebuild.
`./probar.sh` reports any missing text.

## Privacy

The repository holds no personal data: `.csv` reports, `.txt` lists, logs, copy manifests and
any photo or video are excluded in `.gitignore`. Profiles and caches live outside the project,
in `~/Library/Application Support/fotos-iphone/`.

## Roadmap

- **v0.2** (in progress): separate Swift library, configurable filters, interactive assistant,
  saved profiles (“Trip”, “Full backup”…).
- **v0.3**: SwiftUI Mac app on the same library: iPhone status, calendar and options, simulation
  preview with thumbnails, copy with pause and resume, and a separate delete screen.
