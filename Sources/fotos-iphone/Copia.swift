import Foundation
import FotosCore
import FotosIPhoneKit

/// Copia real con red de seguridad: primero simula (solo el resumen), muestra qué se copiaría,
/// qué se descarta y por qué y si cabe en el disco, y pregunta antes de copiar nada.
@MainActor
enum Copia {

    static func simularYCopiar(_ config: Configuracion, catalogo: Catalogo) async throws {
        // Antes de nada: que se pueda escribir en el destino (p. ej. «/Desktop/…» sin ~ no se puede).
        if let d = config.destino, !Disco.sePuedeEscribir(en: d) {
            throw ErrorHerramienta.copia(tr("No se puede escribir en la carpeta de destino %@. Revisa la ruta (¿falta ~ al principio, como en ~/Desktop/…?).", d.path))
        }
        if config.confirmar {
            guard try await simularYConfirmar(config, catalogo: catalogo) else {
                print(tr("Cancelado. No se ha copiado nada."))
                return
            }
            print("")
        }
        var real = config
        real.simular = false
        real.detalle = true
        real.mostrarOpciones = !config.confirmar   // si ya se mostraron en la simulación, no se repiten
        try await Transferencia(config: real, catalogo: catalogo).ejecutar()
    }

    /// true si el usuario confirma la copia.
    static func simularYConfirmar(_ config: Configuracion, catalogo: Catalogo) async throws -> Bool {
        var sim = config
        sim.simular = true
        sim.detalle = false
        sim.mostrarOpciones = true
        print(tr("🧪 Primero, una simulación para ver qué se copiaría…\n"))
        let t = Transferencia(config: sim, catalogo: catalogo)
        try await t.ejecutar()

        let motivos = t.informe.motivosDeDescarte()
        if !motivos.isEmpty {
            print(tr("\n🗑  Se descartaría:"))
            for m in motivos { print(tr("   %ld · %@", m.archivos, m.motivo)) }
        }

        let archivos = t.informe.cantidad(.seCopiaria)
        let mover = t.informe.cantidad(.seReubicaria)
        let yaEstan = t.informe.cantidad(.yaExistia)
        if yaEstan > 0 {
            print(tr("\n✓ %ld archivos ya están copiados en el destino y no se repiten.", yaEstan))
        }
        if mover > 0 {
            print(tr("↪︎ %ld archivos ya copiados están en otras carpetas: se moverán a la organización elegida (sin volver a descargarlos).", mover))
        }
        guard archivos + mover > 0 else {
            print(tr("\nNada que copiar con estas opciones."))
            return false
        }
        guard let destino = config.destino else { return false }
        let bytes = t.informe.bytes
        if let libre = Disco.libre(en: destino) {
            print(tr("\n💽 Espacio libre en el destino: %@ (la copia ocupa hasta %@; lo ya copiado no se repite).",
                     formatoBytes(libre), formatoBytes(bytes)))
            if libre < bytes {
                print(tr("⚠️  Puede que no haya espacio suficiente para todo."))
            }
        }
        let pregunta = archivos > 0
            ? tr("\n¿Copiar ahora %ld archivos (%@) a %@?", archivos, formatoBytes(bytes), destino.path)
            : tr("\n¿Mover ahora %ld archivos a la organización elegida?", mover)
        return try await Consola.siNo(pregunta, porDefecto: false)
    }
}
