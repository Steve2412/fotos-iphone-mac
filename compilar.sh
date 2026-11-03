#!/bin/bash
# Compila la herramienta y deja el ejecutable «fotos-iphone» en esta carpeta,
# junto con sus traducciones (fotos-iphone_FotosCore.bundle).
# La salida completa queda también en compilacion.log.
set -o pipefail
cd "$(dirname "$0")"
if ! swift build -c release --product fotos-iphone 2>&1 | tee compilacion.log; then
    echo ""
    echo "❌ La compilación falló. El detalle está en compilacion.log"
    exit 1
fi
BIN="$(swift build -c release --show-bin-path)"
# Se borra antes de copiar: sobrescribir un ejecutable ya usado invalida su firma
# y macOS lo mata al arrancar («zsh: killed»).
rm -f ./fotos-iphone
cp "$BIN/fotos-iphone" ./fotos-iphone
codesign --force --sign - ./fotos-iphone 2>/dev/null || true
# Traducciones: tienen que estar junto al ejecutable.
rm -rf ./fotos-iphone_FotosCore.bundle
if [ -d "$BIN/fotos-iphone_FotosCore.bundle" ]; then
    cp -R "$BIN/fotos-iphone_FotosCore.bundle" ./
else
    echo "⚠️  No encontré las traducciones en $BIN; la herramienta funcionará solo en español." | tee -a compilacion.log
fi
echo ""
echo "✅ Listo. Prueba:  ./fotos-iphone --ayuda   ·   ./fotos-iphone --language en --help"
