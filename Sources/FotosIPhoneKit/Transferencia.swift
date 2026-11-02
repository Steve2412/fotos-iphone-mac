import Foundation
import CryptoKit
import FotosCore

@MainActor
public final class Transferencia {
    let config: Configuracion
    let catalogo: Catalogo
    let informe = Informe()
    private let fm = FileManager.default
    private var destino: URL!
    private var temporal: URL!

    private var op: Opciones { config.opciones }

    public init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
    }

    public func ejecutar() async throws {
        let entradas: [EntradaAlbum]
        var directos: [Int: Elemento] = [:]
        if config.porFechas {
            let elegidos = catalogo.elementos(en: op.periodo)
            entradas = elegidos.enumerated().map { i, el in
                directos[i] = el
                return EntradaAlbum(linea: i, nombre: el.etiqueta, numero: el.numero ?? 0, fecha: el.fecha)
            }
            guard !entradas.isEmpty else { throw ErrorHerramienta.lista(tr("No hay archivos en ese periodo.")) }
            print(tr("📅 %ld elementos %@.", entradas.count, op.periodo.descripcion))
        } else {
            entradas = try ListaAlbum.leer(config.lista!)
            guard !entradas.isEmpty else { throw ErrorHerramienta.lista(tr("La lista del álbum está vacía.")) }
            print(tr("📝 %ld elementos en la lista del álbum.", entradas.count))
        }

        if config.simular {
            print(tr("🧪 Simulación: no se copiará nada.\n"))
        } else {
            destino = config.destino!
            temporal = destino.appendingPathComponent(".temporal-fotos-iphone", isDirectory: true)
            try? fm.removeItem(at: temporal)
            try fm.createDirectory(at: temporal, withIntermediateDirectories: true)
            print(tr("📂 Destino: %@\n", destino.path))
        }

        var procesados = Set<ObjectIdentifier>()
        for (i, entrada) in entradas.enumerated() {
            let prefijo = "[\(i + 1)/\(entradas.count)] \(entrada.nombre)"
            let busqueda: Busqueda = directos[entrada.linea].map { .encontrado($0) } ?? catalogo.buscar(entrada)
            switch busqueda {
            case .noEncontrado(let motivo):
                print("\(prefijo)  ✗ \(motivo)")
                informe.agregar(entrada: entrada.nombre, archivo: "", tipo: "", resultado: .noEncontrado, motivo: motivo)
            case .encontrado(let el):
                guard procesados.insert(ObjectIdentifier(el)).inserted else {
                    print(tr("%@  (repetido en la lista, ya procesado)", prefijo))
                    continue
                }
                print(tr("%@  · %@ del %@", prefijo, el.descripcion, formatoFecha(el.fecha)))
                await procesar(el, entrada: entrada)
            }
            if !config.simular {
                try? informe.escribir(en: destino.appendingPathComponent("informe.csv"))
            }
        }

        let rutaInforme: URL
        if config.simular {
            rutaInforme = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("informe-simulacion.csv")
        } else {
            try? fm.removeItem(at: temporal)
            rutaInforme = destino.appendingPathComponent("informe.csv")
        }
        try informe.escribir(en: rutaInforme)
        print("\n" + informe.resumen())
        print(tr("📄 Informe: %@", rutaInforme.path))
    }

    // MARK: Un elemento

    private func procesar(_ el: Elemento, entrada: EntradaAlbum) async {
        let decisiones = Reglas.clasificar(el, op)

        func registrar(_ d: Decision, _ resultado: Resultado, _ motivo: String = "", sha: String = "") {
            let nota = motivo.isEmpty ? "" : " — \(motivo)"
            print("     \(resultado.icono) \(d.archivo.nombre)  [\(d.tipo.texto)]  \(resultado.texto)\(nota)")
            informe.agregar(entrada: entrada.nombre, archivo: d.archivo.nombre, tipo: d.tipo.texto,
                            resultado: resultado, motivo: motivo, bytes: d.archivo.tamano, sha: sha)
        }
        func descartarTodo(_ m: Motivo) {
            for d in decisiones { registrar(d, .descartado, m.texto) }
        }
        func descartarSegunReglas() {
            for d in decisiones { registrar(d, .descartado, d.motivo?.texto ?? "") }
        }

        // 0. Sin original en el iPhone, o nada que copiar con estas opciones.
        guard el.imagenOriginal != nil || el.videoOriginal != nil else {
            return descartarTodo(.sinOriginal)
        }
        guard decisiones.contains(where: \.conservar) else {
            return descartarSegunReglas()
        }

        // 1. ¿Su origen (cámara, captura, grabación, otra app) y su cámara están elegidos?
        var videoEnTemporal: URL?
        let pantallas = catalogo.pantallas
        if Reglas.necesitaMetadatos(op) {
            if el.numero == nil || Reglas.esGrabacionDePantalla(el, pantallas: pantallas) {
                // Otra app (nombre que no es IMG_) o grabación de pantalla (resolución de pantalla):
                // el origen se sabe sin leer metadatos ni descargar nada.
                let origen = Reglas.origen(de: el, info: nil, pantallas: pantallas)
                if let m = Reglas.motivoOrigen(origen, info: nil, opciones: op) {
                    return descartarTodo(m)
                }
            } else if let img = el.imagenOriginal {
                let dic = (try? await img.file.leerMetadatos()) ?? [:]
                let info = DatosCamara.info(en: dic)
                if let m = Reglas.motivoOrigen(Reglas.origen(de: el, info: info, pantallas: pantallas), info: info, opciones: op) {
                    return descartarTodo(m)
                }
            } else if let video = el.videoOriginal {
                if config.simular {
                    for d in decisiones {
                        if d.conservar { registrar(d, .seCopiaria, tr("la cámara del vídeo se comprueba al copiar")) }
                        else { registrar(d, .descartado, d.motivo?.texto ?? "") }
                    }
                    return
                }
                do {
                    // En los vídeos los datos de cámara van dentro del archivo: hay que copiarlo para leerlos.
                    let existente = destino.appendingPathComponent(
                        Reglas.rutaRelativa(nombre: video.nombre, fecha: el.fecha, organizacion: op.organizacion))
                    let url: URL
                    if yaCopiado(video, en: existente) {
                        url = existente
                    } else {
                        url = try await descargarTemporal(video)
                        videoEnTemporal = url
                    }
                    let (make, model) = await DatosCamara.makeModelDeVideo(url)
                    let info = InfoCamara(make: make, model: model)
                    if let m = Reglas.motivoOrigen(Reglas.origen(de: el, info: info, pantallas: pantallas), info: info, opciones: op) {
                        if let t = videoEnTemporal { try? fm.removeItem(at: t) }
                        return descartarTodo(m)
                    }
                } catch {
                    for d in decisiones { registrar(d, .error, error.localizedDescription) }
                    return
                }
            }
        }
        defer {
            // Si el vídeo se descargó solo para leer la cámara y no se copia (p. ej. versión final), se borra.
            if let t = videoEnTemporal, fm.fileExists(atPath: t.path) { try? fm.removeItem(at: t) }
        }

        // 2. Copiar lo que se conserva.
        for d in decisiones {
            guard d.conservar else {
                registrar(d, .descartado, d.motivo?.texto ?? "")
                continue
            }
            if config.simular {
                registrar(d, .seCopiaria, formatoBytes(d.archivo.tamano))
                continue
            }
            var final = destino.appendingPathComponent(d.rutaRelativa)
            if yaCopiado(d.archivo, en: final) {
                registrar(d, .yaExistia)
                continue
            }
            var nota = ""
            if fm.fileExists(atPath: final.path) {
                // Mismo nombre pero distinto archivo (el contador IMG_ dio la vuelta).
                final = rutaLibre(junto: final)
                nota = tr("ya había otro %@; guardado como %@", d.archivo.nombre, final.lastPathComponent)
            }
            do {
                try fm.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
                let tmp: URL
                if d.archivo === el.videoOriginal, let v = videoEnTemporal {
                    tmp = v
                } else {
                    tmp = try await descargarTemporal(d.archivo)
                }
                let tam = tamano(de: tmp)
                if tam != d.archivo.tamano {
                    let aviso = tr("tamaño copiado %lld bytes, el iPhone indica %lld", tam, d.archivo.tamano)
                    nota = nota.isEmpty ? aviso : nota + "; " + aviso
                }
                try fm.moveItem(at: tmp, to: final)
                if let fecha = el.fecha {
                    try? fm.setAttributes([.creationDate: fecha, .modificationDate: fecha], ofItemAtPath: final.path)
                }
                let sha = op.sha256 ? ((try? sha256(final)) ?? "") : ""
                registrar(d, tam == d.archivo.tamano ? .copiado : .copiadoConAviso, nota, sha: sha)
            } catch {
                registrar(d, .error, error.localizedDescription)
            }
        }
    }

    // MARK: Archivos

    private func descargarTemporal(_ a: Archivo) async throws -> URL {
        print("       ↓ \(a.nombre) (\(formatoBytes(a.tamano)))")
        let tmp = temporal.appendingPathComponent(a.nombre)
        try? fm.removeItem(at: tmp)
        return try await a.file.descargar(en: temporal, como: a.nombre)
    }

    private func tamano(de url: URL) -> Int64 {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func yaCopiado(_ a: Archivo, en url: URL) -> Bool {
        fm.fileExists(atPath: url.path) && tamano(de: url) == a.tamano
    }

    /// «IMG_0001 (2).HEIC», «IMG_0001 (3).HEIC»… en la misma carpeta que `url`.
    private func rutaLibre(junto url: URL) -> URL {
        let carpeta = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let candidato = carpeta.appendingPathComponent("\(base) (\(n)).\(ext)")
            if !fm.fileExists(atPath: candidato.path) { return candidato }
            n += 1
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let datos = try h.read(upToCount: 8 << 20), !datos.isEmpty {
            hasher.update(data: datos)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
