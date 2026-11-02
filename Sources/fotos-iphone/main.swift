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
        case .inspeccionar:
            await Inspector(config: config, catalogo: catalogo).ejecutar()
        case .volcar:
            try Volcado.escribir(camara: camara)
        case .transferir where config.borrar:
            try await Borrado(config: config, catalogo: catalogo, camara: camara).ejecutar()
        case .transferir:
            try await Transferencia(config: config, catalogo: catalogo).ejecutar()
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
    } catch {
        print("\n❌ \(error.localizedDescription)")
        exit(1)
    }
}

RunLoop.main.run()
