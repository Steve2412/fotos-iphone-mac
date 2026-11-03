import Foundation
import CryptoKit
import FotosCore

@MainActor
public final class Transferencia {
    let config: Configuracion
    let catalogo: Catalogo
    public let informe = Informe()
    let lector: LectorCamara
    private var manifiesto = Manifiesto()
    /// Archivos movidos a otra carpeta por cambiar la organización.
    private var reubicados = 0
    private let fm = FileManager.default
    private var destino: URL!
    private var temporal: URL!

    private var op: Opciones { config.opciones }

    public init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
        self.lector = LectorCamara()
    }

    public func ejecutar() async throws {
        if config.mostrarOpciones {
            print(tr("⚙️  Opciones:"))
            for linea in op.resumen { print("   · " + linea) }
            print("")
        }

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
            // Con destino conocido, la simulación también dice qué está ya copiado o se movería.
            if let d = config.destino {
                destino = d.standardizedFileURL
                manifiesto = Manifiesto.leer(en: destino)
            }
        } else {
            destino = config.destino!.standardizedFileURL
            temporal = destino.appendingPathComponent(".temporal-fotos-iphone", isDirectory: true)
            try? fm.removeItem(at: temporal)
            try fm.createDirectory(at: temporal, withIntermediateDirectories: true)
            manifiesto = Manifiesto.leer(en: destino)
            print(tr("📂 Destino: %@\n", destino.path))
        }

        var procesados = Set<ObjectIdentifier>()
        for (i, entrada) in entradas.enumerated() {
            let prefijo = "[\(i + 1)/\(entradas.count)] \(entrada.nombre)"
            let busqueda: Busqueda = directos[entrada.linea].map { .encontrado($0) } ?? catalogo.buscar(entrada)
            switch busqueda {
            case .noEncontrado(let motivo):
                if config.detalle { print("\(prefijo)  ✗ \(motivo)") }
                informe.agregar(entrada: entrada.nombre, archivo: "", tipo: "", resultado: .noEncontrado, motivo: motivo)
            case .encontrado(let el):
                guard procesados.insert(ObjectIdentifier(el)).inserted else {
                    print(tr("%@  (repetido en la lista, ya procesado)", prefijo))
                    continue
                }
                if config.detalle {
                    print(tr("%@  · %@ del %@", prefijo, el.descripcion, formatoFecha(el.fecha)))
                }
                await procesar(el, entrada: entrada)
            }
            if !config.simular {
                try? informe.escribir(en: destino.appendingPathComponent("informe.csv"))
                try? manifiesto.escribir(en: destino)
            }
            if (i + 1) % 200 == 0 { lector.guardar() }
            if !config.detalle && ((i + 1) % 100 == 0 || i + 1 == entradas.count) {
                print(tr("   … %ld/%ld", i + 1, entradas.count))
            }
        }
        lector.guardar()

        let rutaInforme: URL
        if config.simular {
            rutaInforme = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("informe-simulacion.csv")
        } else {
            try? fm.removeItem(at: temporal)
            try? manifiesto.escribir(en: destino)
            rutaInforme = destino.appendingPathComponent("informe.csv")
        }
        try informe.escribir(en: rutaInforme)
        print("\n" + informe.resumen())
        if lector.videosSinLeer > 0 {
            print(tr("   ⚠️  %ld vídeos sin cabecera legible: su cámara se comprueba al copiar.", lector.videosSinLeer))
        }
        if reubicados > 0 {
            print(tr("   ↪︎ %ld archivos ya copiados se movieron a la organización elegida. Las carpetas antiguas que hayan quedado vacías puedes borrarlas desde el Finder.", reubicados))
        }
        print(tr("📄 Informe: %@", rutaInforme.path))
    }

    // MARK: Un elemento

    private func procesar(_ el: Elemento, entrada: EntradaAlbum) async {
        let decisiones = Reglas.clasificar(el, op)

        func registrar(_ d: Decision, _ resultado: Resultado, _ motivo: String = "", sha: String = "") {
            if config.detalle {
                let nota = motivo.isEmpty ? "" : " — \(motivo)"
                print("     \(resultado.icono) \(d.archivo.nombre)  [\(d.tipo.texto)]  \(resultado.texto)\(nota)")
            }
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
        func motivoOrigen(_ info: InfoCamara?) -> Motivo? {
            Reglas.motivoOrigen(Reglas.origen(de: el, info: info, pantallas: pantallas), info: info, opciones: op)
        }
        if Reglas.necesitaMetadatos(op) {
            if el.numero == nil || Reglas.esGrabacionDePantalla(el, pantallas: pantallas) {
                // Otra app (nombre que no es IMG_) o grabación de pantalla (resolución de pantalla):
                // el origen se sabe sin leer metadatos ni descargar nada.
                if let m = motivoOrigen(nil) { return descartarTodo(m) }
            } else if let img = el.imagenOriginal {
                let info = await lector.infoFoto(img)
                if let m = motivoOrigen(info) { return descartarTodo(m) }
            } else if let video = el.videoOriginal {
                if let info = await lector.infoVideo(video) {
                    // Leída de la cabecera del vídeo, sin descargarlo.
                    if let m = motivoOrigen(info) { return descartarTodo(m) }
                } else if config.simular {
                    for d in decisiones {
                        if d.conservar { registrar(d, .seCopiaria, tr("la cámara del vídeo se comprueba al copiar")) }
                        else { registrar(d, .descartado, d.motivo?.texto ?? "") }
                    }
                    return
                } else {
                    do {
                        // No se pudo leer la cabecera: se descarga el vídeo para leer su cámara.
                        let url: URL
                        if let existente = rutaExistente(video, para: el) {
                            url = existente
                        } else {
                            url = try await descargarTemporal(video)
                            videoEnTemporal = url
                        }
                        let (make, model) = await DatosCamara.makeModelDeVideo(url)
                        let info = InfoCamara(make: make, model: model)
                        lector.recordar(video, info)
                        if let m = motivoOrigen(info) {
                            if let t = videoEnTemporal { try? fm.removeItem(at: t) }
                            return descartarTodo(m)
                        }
                    } catch {
                        for d in decisiones { registrar(d, .error, error.localizedDescription) }
                        return
                    }
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
            if destino != nil, let existente = rutaExistente(d.archivo, para: el) {
                // Ya copiado antes (según el manifiesto, o en su ruta con el mismo tamaño).
                reubicarSiHaceFalta(d, existente: existente, elemento: el, registrar: registrar)
                continue
            }
            if config.simular {
                registrar(d, .seCopiaria, formatoBytes(d.archivo.tamano))
                continue
            }
            var final = destino.appendingPathComponent(d.rutaRelativa)
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
                if tam == d.archivo.tamano {
                    manifiesto.registrar(d.archivo, ruta: relativa(final), elemento: el.etiqueta, sha256: sha)
                }
                registrar(d, tam == d.archivo.tamano ? .copiado : .copiadoConAviso, nota, sha: sha)
            } catch {
                registrar(d, .error, error.localizedDescription)
            }
        }
    }

    /// Un archivo ya copiado: si está en la carpeta que le toca con la organización elegida, «ya existía»;
    /// si está en otra (se copió con otra organización), se mueve dentro del destino a la que le toca,
    /// sin volver a descargarlo. Nunca se sobrescribe otro archivo.
    private func reubicarSiHaceFalta(_ d: Decision, existente: URL, elemento el: Elemento,
                                     registrar: (Decision, Resultado, String, String) -> Void) {
        let sha = manifiesto.entradas[d.archivo.identidad]?.sha256
        let actual = relativa(existente)
        let carpetaActual = (actual as NSString).deletingLastPathComponent
        let carpetaPrevista = (d.rutaRelativa as NSString).deletingLastPathComponent
        guard carpetaActual != carpetaPrevista else {
            if !config.simular {
                manifiesto.registrar(d.archivo, ruta: actual, elemento: el.etiqueta, sha256: sha)
            }
            registrar(d, .yaExistia, "", "")
            return
        }
        var prevista = destino.appendingPathComponent(d.rutaRelativa)
        if fm.fileExists(atPath: prevista.path) {
            // Ya hay otro archivo con ese nombre en la carpeta nueva: se busca un nombre libre.
            prevista = rutaLibre(junto: prevista)
        }
        let nota = tr("de %@ a %@", actual, relativa(prevista))
        if config.simular {
            registrar(d, .seReubicaria, nota, "")
            return
        }
        do {
            try fm.createDirectory(at: prevista.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: existente, to: prevista)
            manifiesto.registrar(d.archivo, ruta: relativa(prevista), elemento: el.etiqueta, sha256: sha)
            reubicados += 1
            registrar(d, .reubicado, nota, "")
        } catch {
            // No se pudo mover: se deja donde estaba, que sigue siendo un respaldo válido.
            manifiesto.registrar(d.archivo, ruta: actual, elemento: el.etiqueta, sha256: sha)
            registrar(d, .yaExistia, tr("no se pudo mover a %@: %@", d.rutaRelativa, error.localizedDescription), "")
        }
    }

    // MARK: Archivos

    /// Dónde está ya copiado este archivo con el tamaño correcto: primero según el manifiesto
    /// (sirve aunque se renombrara o se cambiara la organización), luego en su ruta prevista.
    private func rutaExistente(_ a: Archivo, para el: Elemento) -> URL? {
        if let r = manifiesto.ruta(de: a) {
            let url = destino.appendingPathComponent(r)
            if yaCopiado(a, en: url) { return url }
        }
        let prevista = destino.appendingPathComponent(
            Reglas.rutaRelativa(nombre: a.nombre, fecha: el.fecha, organizacion: op.organizacion))
        return yaCopiado(a, en: prevista) ? prevista : nil
    }

    /// Ruta de `url` relativa a la carpeta de destino.
    private func relativa(_ url: URL) -> String {
        let base = destino.path.hasSuffix("/") ? destino.path : destino.path + "/"
        let ruta = url.standardizedFileURL.path
        return ruta.hasPrefix(base) ? String(ruta.dropFirst(base.count)) : url.lastPathComponent
    }

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
