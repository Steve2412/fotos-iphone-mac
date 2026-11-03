import Foundation
import ImageCaptureCore
import FotosCore
import FotosIPhoneKit

/// `--borrar`: muestra qué se borraría del iPhone y, si no es una simulación, pide escribir
/// una clave («BORRAR 3») antes de borrar. --si nunca se salta esta confirmación.
@MainActor
enum BorradoTerminal {

    static func ejecutar(_ config: Configuracion, catalogo: Catalogo, camara: ICCameraDevice) async throws {
        let borrado = Borrado(config: config, catalogo: catalogo, camara: camara)
        let plan = try borrado.planificar()
        borrado.mostrar(plan)

        guard !plan.aBorrar.isEmpty else {
            print(tr("\nNada que borrar."))
            return
        }
        if config.simular {
            print(tr("\n🧪 Simulación: no se ha borrado nada."))
            return
        }

        print(tr("\n⚠️  ATENCIÓN\n   · El borrado por cable es definitivo: NO pasa por «Eliminados recientemente».\n   · Si usas Fotos de iCloud, también se borran de iCloud y de tus otros dispositivos."))
        let clave = tr("BORRAR %ld", plan.aBorrar.count)
        let respuesta: String
        do {
            respuesta = try await Consola.texto(
                tr("Para continuar escribe exactamente «%@» (cualquier otra cosa cancela)", clave), porDefecto: "")
        } catch ErrorHerramienta.cancelado {
            respuesta = ""
        }
        guard respuesta == clave else {
            print(tr("Cancelado. No se ha borrado nada."))
            return
        }

        let r = await borrado.ejecutar(plan)
        print(tr("\n📊 Archivos borrados: %ld · no borrados: %ld", r.borrados, r.fallidos))
        print(tr("📄 Informe: %@", r.informe.path))
        print(tr("Desconecta y vuelve a conectar el cable antes de volver a usar la herramienta."))
    }
}
