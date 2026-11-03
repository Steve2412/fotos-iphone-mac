# fotos-iphone

**English** · [Español](README.es.md)

A macOS tool that copies the **original** photos and videos from an iPhone to a Mac over **USB**
(HEIC, DNG, MOV… with no conversion and all their metadata), using `ImageCaptureCore`.

> **Status:** v0.3. A **Mac app** (SwiftUI) and a **Terminal** tool on the same library.

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
- Reads the camera of videos from their header only (a few KB), without downloading them.
- Copies safely: downloads to a temporary folder, checks the size, then moves it into place.
  It can be interrupted and resumed (what was already copied is skipped). Writes an `informe.csv` report
  and a manifest (`.fotos-iphone/manifiesto.json` in the destination) recording where each file went.
- Messages in **English and Spanish** (ready for more languages).

## Requirements

- A Mac with macOS 14 or later and the Xcode developer tools.
- On the iPhone: *Settings → Apps → Photos → Transfer to Mac or PC → **Keep Originals***.
- When copying or simulating: iPhone unlocked and connected by cable, with Auto-Lock set to *Never*;
  **Image Capture open** and Photos closed on the Mac.

## Build and test

```bash
./compilar.sh     # builds ./fotos-iphone and its translations; errors go to compilacion.log
./probar.sh       # tests that don't need an iPhone; output in pruebas.log
./empaquetar-app.sh && open "Fotos iPhone.app"   # the Mac app; errors in compilacion-app.log
```

## Mac app

`./empaquetar-app.sh` builds **Fotos iPhone.app** in the project folder (you can move it to
Applications). It uses the same options, profiles and caches as the Terminal tool.

1. **On launch** it checks that Image Capture is open and opens it if not (without it macOS doesn't
   deliver the iPhone's photos). If the catalog doesn't arrive, it tells you what to do. While
   connecting, **Stop** cancels the attempt and **Reconnect** tries again.
2. **Options** (left panel): profile, period (including *last month*), sources, cameras
   (*this iPhone*, worked out from its recent photos; any; or chosen ones), versions, videos, RAW,
   layout and destination. Profiles can be saved, updated (it confirms) and deleted (except the
   built-in ones).
3. **Simulate** shows what would be copied, what is already copied and what is skipped and why, with
   thumbnails requested from the iPhone (without downloading the files). Click one to see each file.
4. **Copy…** is only enabled after an up-to-date simulation, and asks for confirmation. It shows
   progress, speed and time left; you can **pause**, **resume** and **cancel** (when the current
   file finishes). The Mac doesn't sleep during the copy.
5. **Delete from iPhone** (selector at the top): items from the period that are in the destination
   folder, or what a previous copy copied (its `informe.csv`). First you **review** what would be
   deleted and, to delete, you type the key (“DELETE 12”). Every deletion is checked on the iPhone.
6. Closing the window quits the app. With a copy or deletion in progress, it asks first.
7. **Settings** (⌘,): app language (system, Spanish or English).

## Terminal

### Assistant

With no options, the tool asks step by step what to copy (period, sources, cameras found on the
iPhone, versions, videos, RAW, layout and destination), using your last choices as defaults. At the
end it simulates, shows what would be copied, what is skipped and why, and whether it fits on the
disk, and **asks for confirmation before copying**. The options can be saved as a profile.

```bash
./fotos-iphone
```

### Profiles

Three come built in and you can save your own:

| Profile | What it copies |
|---|---|
| Full backup | The whole camera roll, any source and camera, original + edited, with Live Photo videos, by year and month |
| Recent days backup | The last 7 days, any camera, final version, by day |
| Trip | Photos and videos from this iPhone's camera (like v0.1) in the date range you give |

They are stored in `~/Library/Application Support/fotos-iphone/perfiles/`. Saving with a name that already exists updates it (and says so). Built-in profiles can't be deleted; if you update one, deleting your version restores the original.

“This iPhone” is the default camera: the iPhone doesn't report its model over the cable, so it is worked out from its recent photos (Camera photos carry the model in their metadata).

```bash
./fotos-iphone --profiles                                   # list them
./fotos-iphone --profile "Full backup" --dest ~/Pictures/iPhone
./fotos-iphone --profile Trip --from 2026-10-01 --to 2026-10-15 --dest ~/Pictures/Trip
./fotos-iphone --sources screenshots --layout month --save-profile "Screenshots"
./fotos-iphone --delete-profile "Screenshots"
```

### With options

A real copy always simulates first and asks; `--yes` copies without asking.

```bash
# Detailed simulation
./fotos-iphone --from 2026-10-01 --to 2026-10-31 --simulate

# Real copy
./fotos-iphone --from 2026-10-01 --to 2026-10-31 --dest ~/Pictures/iPhone-Backup

# Screenshots and files from other apps from the last week, organized by month
./fotos-iphone --days 7 --sources screenshots,apps --layout month --simulate

# Everything from last month (the whole previous calendar month)
./fotos-iphone --last-month --dest ~/Pictures/Month --simulate

# The whole camera roll, any camera, final version only, videos up to 2 GB
./fotos-iphone --all --sources all --any-camera --versions final --max-video 2GB --simulate

# Which cameras and sources are on the iPhone?
./fotos-iphone --cameras

# See how the Mac recognizes the latest items (source, camera, groups…)
./fotos-iphone --inspect --last 20

./fotos-iphone --help
```

Every option is accepted in English and Spanish (`--from` = `--desde`, `--dest` = `--destino`…).
`--language en` or `--idioma es` force the language of the messages (default: the system's).

> **Deleting from the iPhone (`--delete`).** Deleting over the cable is permanent (it does not go
> to “Recently Deleted”) and, with iCloud Photos, it also deletes from iCloud. It only touches items
> whose original and edit are in the backup, asks you to type a key, and then checks on the iPhone
> that each photo was really deleted. With `--report informe.csv` the candidates come from a copy's report:
>
> ```bash
> ./fotos-iphone --delete --simulate --report ~/Pictures/Backup/informe.csv
> ```

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
Sources/FotosIPhoneApp/   Mac app (SwiftUI)
App/                      Info.plist, icon (AppIcon.icns) and its generator (generar-icono.py)
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

- **v0.2** ✓: separate Swift library, configurable filters, languages, interactive assistant,
  profiles and verified deletion.
- **v0.3** ✓: SwiftUI Mac app on the same library: iPhone status, options and profiles, simulation
  preview with thumbnails, copy with pause and resume, deletion from the folder or from an
  `informe.csv`, language in Settings and an icon.
