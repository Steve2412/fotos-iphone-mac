import Foundation
import ImageCaptureCore
import FotosCore
import FotosIPhoneKit

// Salida línea a línea, para ver el progreso en tiempo real.
setvbuf(stdout, nil, _IOLBF, 0)

let argumentos = Array(CommandLine.arguments.dropFirst())

// El idioma se elige antes que nada, para que hasta los errores de los argumentos salgan traducidos.
let idiomaPedido = Configuracion.idiomaPedido(en: argumentos)
let idiomaUsado = Idioma.elegir(idiomaPedido)
if let pedido = idiomaPedido, !pedido.lowercased().hasPrefix(idiomaUsado.lowercased()) {
    fputs(tr("⚠️  El idioma «%@» no está disponible; uso «%@». Disponibles: %@.", pedido, idiomaUsado,
             Idioma.disponibles.joined(separator: ", ")) + "\n", stderr)
}

let configuracion: Configuracion = {
    do {
        return try Configuracion(argumentos: argumentos)
    } catch {
        fputs("❌ \(error.localizedDescription)\n\n", stderr)
        print(Configuracion.ayuda)
        exit(2)
    }
}()

func mostrarPerfiles() {
    print(tr("📋 Perfiles (úsalos con --perfil \"NOMBRE\"):"))
    for p in Perfiles.todos() {
        print("\n• \(p.nombreVisible)" + (Perfiles.esIntegrado(p) ? tr(" (integrado)") : ""))
        for l in p.opciones.resumen { print("     · " + l) }
        if let d = p.destino { print("     · " + tr("Destino: %@", d)) }
    }
    if let carpeta = Perfiles.carpetaPorDefecto {
        print(tr("\nLos perfiles que guardes van en %@", carpeta.path))
    }
}

// Perfiles: se gestionan sin conectar el iPhone.
if let nombre = configuracion.guardarPerfil {
    do {
        let destino = configuracion.destino.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        let url = try Perfiles.guardar(Perfil(nombre: nombre, opciones: configuracion.opciones, destino: destino))
        print(tr("💾 Perfil «%@» guardado en %@", nombre, url.path))
        for l in configuracion.opciones.resumen { print("   · " + l) }
        print("")
    } catch {
        fputs("❌ \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
switch configuracion.modo {
case .perfiles:
    mostrarPerfiles()
    exit(0)
case .guardarPerfil:
    exit(0)
default:
    break
}

@MainActor
final class Programa {
    let config: Configuracion
    let conexion = ConexionIPhone()

    init(config: Configuracion) {
        self.config = config
    }

    func ejecutar() async throws {
        let camara = try await conexion.conectar()
        let catalogo = Catalogo(camara: camara)
        print(tr("📚 El iPhone muestra %ld archivos.\n", catalogo.cantidadArchivos))

        switch config.modo {
        case .asistente:
            try await Asistente(config: config, catalogo: catalogo).ejecutar()
        case .perfiles, .guardarPerfil:
            break
        case .inspeccionar:
            await Inspector(config: config, catalogo: catalogo).ejecutar()
        case .camaras:
            await ListaCamaras(config: config, catalogo: catalogo).ejecutar()
        case .volcar:
            try Volcado.escribir(camara: camara)
        case .transferir where config.borrar:
            try await BorradoTerminal.ejecutar(config, catalogo: catalogo, camara: camara)
        case .transferir where config.simular:
            try await Transferencia(config: config, catalogo: catalogo).ejecutar()
        case .transferir:
            // Copia real: simula, muestra el resumen y pregunta (salvo con --si).
            try await Copia.simularYCopiar(config, catalogo: catalogo)
        }
        conexion.cerrar()
    }
}

// Mantiene vivo el bucle principal: ImageCaptureCore entrega sus avisos en él.
_ = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in }

Task { @MainActor in
    do {
        try await Programa(config: configuracion).ejecutar()
        exit(0)
    } catch ErrorHerramienta.cancelado {
        print("\n" + ErrorHerramienta.cancelado.localizedDescription)
        exit(0)
    } catch {
        print("\n❌ \(error.localizedDescription)")
        exit(1)
    }
}

RunLoop.main.run()
