#!/bin/bash
# Ejecuta las pruebas de FotosCore (no necesitan el iPhone).
# La salida completa queda también en pruebas.log.
set -o pipefail
cd "$(dirname "$0")"
if ! swift test 2>&1 | tee pruebas.log; then
    echo ""
    echo "❌ Alguna prueba falló (o no compiló). El detalle está en pruebas.log"
    exit 1
fi
echo ""
echo "✅ Todas las pruebas pasan."
