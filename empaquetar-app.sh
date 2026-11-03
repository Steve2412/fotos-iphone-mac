#!/bin/bash
# Compila la app y la monta como «Fotos iPhone.app» en esta carpeta.
# La salida de la compilación queda también en compilacion-app.log.
set -o pipefail
cd "$(dirname "$0")"

if ! swift build -c release --product FotosIPhoneApp 2>&1 | tee compilacion-app.log; then
    echo ""
    echo "❌ La compilación de la app falló. El detalle está en compilacion-app.log"
    exit 1
fi
BIN="$(swift build -c release --show-bin-path)"
APP="Fotos iPhone.app"

# Se rehace entera cada vez (es un resultado de la compilación, como el ejecutable de Terminal).
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/es.lproj" "$APP/Contents/Resources/en.lproj"
cp "$BIN/FotosIPhoneApp" "$APP/Contents/MacOS/FotosIPhoneApp"
cp App/Info.plist "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Traducciones de la biblioteca (las busca en Contents/Resources).
if [ -d "$BIN/fotos-iphone_FotosCore.bundle" ]; then
    cp -R "$BIN/fotos-iphone_FotosCore.bundle" "$APP/Contents/Resources/"
else
    echo "⚠️  No encontré las traducciones en $BIN; la app funcionará solo en español." | tee -a compilacion-app.log
fi

# Firma local (sin cuenta de desarrollador). Si fallara, el ejecutable ya trae la firma del enlazador.
if ! codesign --force --sign - "$APP" >>compilacion-app.log 2>&1; then
    echo "⚠️  No se pudo firmar la app (detalle en compilacion-app.log); debería abrir igualmente." | tee -a compilacion-app.log
fi

echo ""
echo "✅ Listo: open \"$APP\""
