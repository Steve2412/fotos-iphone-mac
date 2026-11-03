import Foundation
import ImageCaptureCore
import FotosCore

/// Borra del iPhone solo los elementos cuyo respaldo está completo en la carpeta de destino:
/// todos los archivos que la herramienta guarda (original, editada, .AAE) deben existir allí
/// con el mismo tamaño que en el iPhone. Lo demás no se toca.
/// EXPERIMENTAL: compilado pero sin probar contra el iPhone.
@MainActor
public final class Borrado {
    let config: Configuracion
    let catalogo: Catalogo
    let camara: ICCameraDevice
    private let fm = FileManager.default
    private var manifiesto = Manifiesto()

    public init(config: Configuracion, catalogo: Catalogo, camara: ICCameraDevice) {
        self.config = config
        self.catalogo = catalogo
        self.camara = camara
    }

    private enum Estado { case respaldado, noRespaldado, incompleto(String) }

    public func ejecutar() async throws {
        let destino = config.destino!
        guard fm.fileExists(atPath: destino.path) else {
            throw ErrorHerramienta.argumentos(tr("No existe la carpeta del respaldo: %@", destino.path))
        }
        print(tr("🗂  Comprobando el respaldo en %@\n", destino.path))
        manifiesto = Manifiesto.leer(en: destino)

        var aBorrar: [Elemento] = []
        var noRespaldados = 0
        var incompletos: [(Elemento, String)] = []
        for el in try elementos() {
            switch estado(de: el, en: destino) {
            case .respaldado: aBorrar.append(el)
            case .noRespaldado: noRespaldados += 1
            case .incompleto(let m): incompletos.append((el, m))
            }
        }

        let archivos = aBorrar.flatMap(\.archivos)
        let bytes = archivos.reduce(Int64(0)) { $0 + $1.tamano }
        print(tr("🧹 Se borrarían del iPhone %ld elementos (%ld archivos, %@,", aBorrar.count, archivos.count, formatoBytes(bytes)))
        print(tr("   incluidos los vídeos de sus Live Photos)."))
        print(tr("   No se tocan %ld elementos que no están en el respaldo (orígenes o cámaras no elegidos…).", noRespaldados))
        if !incompletos.isEmpty {
            print(tr("   ⚠️  No se tocan %ld elementos con respaldo incompleto:", incompletos.count))
            for (el, m) in incompletos.prefix(20) { print("      \(el.etiqueta): \(m)") }
            if incompletos.count > 20 { print("      …") }
        }

        guard !aBorrar.isEmpty else { print(tr("\nNada que borrar.")); return }

        if config.simular {
            print(tr("\n🧪 Simulación: no se ha borrado nada."))
            return
        }

        print(tr("\n⚠️  ATENCIÓN\n   · El borrado por cable es definitivo: NO pasa por «Eliminados recientemente».\n   · Si usas Fotos de iCloud, también se borran de iCloud y de tus otros dispositivos."))
        let clave = tr("BORRAR %ld", aBorrar.count)
        print(tr("Para continuar escribe exactamente «%@» y pulsa Intro (cualquier otra cosa cancela): ", clave), terminator: "")
        guard readLine()?.trimmingCharacters(in: .whitespaces) == clave else {
            print(tr("Cancelado. No se ha borrado nada."))
            return
        }

        var informe = "\u{FEFF}" + tr("archivo;resultado") + "\n"
        var borrados = 0
        var fallidos = 0
        let lote = 50
        for inicio in stride(from: 0, to: aBorrar.count, by: lote) {
            let grupo = Array(aBorrar[inicio..<min(inicio + lote, aBorrar.count)])
            let items: [ICCameraItem] = grupo.flatMap { $0.archivos.map(\.file) }
            do {
                let malos = Set(try await camara.borrar(items))
                for a in grupo.flatMap(\.archivos) {
                    let ok = !malos.contains(a.nombre)
                    informe += "\(a.nombre);\(ok ? tr("borrado") : tr("no se pudo borrar"))\n"
                    if ok { borrados += 1 } else { fallidos += 1 }
                }
            } catch {
                for a in grupo.flatMap(\.archivos) { informe += "\(a.nombre);" + tr("error: %@", error.localizedDescription) + "\n" }
                fallidos += items.count
                print(tr("   ✗ Error en un lote: %@", error.localizedDescription))
            }
            print(tr("   … %ld/%ld elementos", min(inicio + lote, aBorrar.count), aBorrar.count))
        }
        let ruta = destino.appendingPathComponent("informe-borrado.csv")
        try? informe.write(to: ruta, atomically: true, encoding: .utf8)
        print(tr("\n📊 Archivos borrados: %ld · no borrados: %ld", borrados, fallidos))
        print(tr("📄 Informe: %@", ruta.path))
        print(tr("Desconecta y vuelve a conectar el cable antes de volver a usar la herramienta."))
    }

    /// Los mismos elementos que se eligen al copiar (rango de fechas o lista del álbum).
    private func elementos() throws -> [Elemento] {
        if config.porFechas {
            return catalogo.elementos(en: config.opciones.periodo)
        }
        var vistos = Set<ObjectIdentifier>()
        var res: [Elemento] = []
        for e in try ListaAlbum.leer(config.lista!) {
            if case .encontrado(let el) = catalogo.buscar(e), vistos.insert(ObjectIdentifier(el)).inserted {
                res.append(el)
            }
        }
        return res
    }

    private func estado(de el: Elemento, en destino: URL) -> Estado {
        // Se buscan con las mismas opciones (versiones, organización…) con las que se copió.
        let guardables = Reglas.clasificar(el, config.opciones).filter(\.conservar)
        guard !guardables.isEmpty else { return .noRespaldado }
        var faltan: [String] = []
        var presentes = 0
        for d in guardables {
            let a = d.archivo
            // Donde lo apuntó la copia (manifiesto) o, si no consta, donde le tocaría ir.
            let url = destino.appendingPathComponent(manifiesto.ruta(de: a) ?? d.rutaRelativa)
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let tam = (attrs?[.size] as? NSNumber)?.int64Value
            if tam == a.tamano { presentes += 1 }
            else { faltan.append(tam == nil ? tr("falta %@", a.nombre) : tr("%@ con otro tamaño", a.nombre)) }
        }
        if faltan.isEmpty { return .respaldado }
        if presentes == 0 { return .noRespaldado }
        return .incompleto(faltan.joined(separator: ", "))
    }
}

private final class Fallidos: @unchecked Sendable {
    var nombres: [String] = []
}

extension ICCameraDevice {
    /// Borra archivos del iPhone. Devuelve los nombres de los que no se pudieron borrar.
    @MainActor
    func borrar(_ items: [ICCameraItem]) async throws -> [String] {
        let fallidos = Fallidos()
        return try await withCheckedThrowingContinuation { cont in
            _ = requestDeleteFiles(items, deleteFailed: { dic in
                fallidos.nombres += dic.values.compactMap { $0.name }
            }, completion: { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: fallidos.nombres)
                }
            })
        }
    }
}
