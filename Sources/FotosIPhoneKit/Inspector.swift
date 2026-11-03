import Foundation
import ImageCaptureCore
import FotosCore

/// Muestra cómo ve el Mac los archivos del iPhone, para comprobar nombres,
/// agrupación y filtro de cámara antes de copiar nada.
@MainActor
public final class Inspector {
    let config: Configuracion
    let catalogo: Catalogo
    /// Para comprobar el lector de cabeceras: siempre lee del iPhone.
    private let lectorSinCache: LectorCamara

    public init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
        self.lectorSinCache = LectorCamara(usarCache: false)
    }

    public func ejecutar() async {
        print(tr("📊 Tipos de archivo en el iPhone:"))
        let porTipo = Dictionary(grouping: catalogo.archivos) { a in
            (a.marca.isEmpty ? "" : "IMG_\(a.marca)… ") + "." + a.ext
        }
        for (tipo, lista) in porTipo.sorted(by: { $0.value.count > $1.value.count }) {
            print("   \(tipo.padding(toLength: 16, withPad: " ", startingAt: 0)) \(lista.count)")
        }
        if !catalogo.sinNumero.isEmpty {
            let ejemplos = catalogo.sinNumero.prefix(5).map(\.nombre).joined(separator: ", ")
            print(tr("   Archivos de otras apps (sin IMG_): %ld (p. ej. %@)", catalogo.sinNumero.count, ejemplos))
        }

        let pantallas = catalogo.pantallas.subtracting(Resolucion.pantallasConocidas).map(\.description).sorted()
        if !pantallas.isEmpty {
            print(tr("   Pantallas deducidas de las capturas: %@", pantallas.joined(separator: ", ")))
        }

        let todos = catalogo.todosLosElementos
        var elegidos: [Elemento]
        if config.numeros.isEmpty && config.nombres.isEmpty {
            elegidos = Array(todos.sorted { ($0.ultimaActividad ?? .distantPast) > ($1.ultimaActividad ?? .distantPast) }.prefix(config.ultimos))
        } else {
            elegidos = Catalogo.filtrar(todos, numeros: config.numeros, nombres: config.nombres)
        }
        elegidos.sort { ($0.fecha ?? .distantPast) < ($1.fecha ?? .distantPast) }

        print(tr("\n🔎 %ld elementos (✓ se guardaría, – se descartaría):", elegidos.count))
        for el in elegidos {
            print("\n\(el.etiqueta)  \(formatoFecha(el.fecha))  \(el.descripcion)")
            if let img = el.imagenOriginal {
                let dic = (try? await img.file.leerMetadatos()) ?? [:]
                let info = DatosCamara.info(en: dic)
                let origen = Reglas.origen(de: el, info: info, pantallas: catalogo.pantallas)
                let ok = Reglas.motivoOrigen(origen, info: info, opciones: config.opciones) == nil
                print(tr("   cámara: %@ / %@  · origen: %@  → %@", info.make ?? "—", info.model ?? "—", origen.texto, ok ? tr("pasa el filtro") : tr("se descartaría el elemento")))
                // Pistas para verificar cómo se reconoce cada origen.
                let tiff = dic["{TIFF}"] as? [AnyHashable: Any]
                var pistas: [String] = []
                if let c = info.comentario { pistas.append(tr("comentario: %@", c)) }
                if let s = tiff?["Software"] as? String { pistas.append(tr("software: %@", s)) }
                if let w = dic["PixelWidth"] as? NSNumber, let h = dic["PixelHeight"] as? NSNumber {
                    pistas.append(tr("píxeles: %@×%@", w.stringValue, h.stringValue))
                }
                if !pistas.isEmpty { print("   " + pistas.joined(separator: " · ")) }
            } else if let video = el.videoOriginal {
                let conocido = el.numero == nil || Reglas.esGrabacionDePantalla(el, pantallas: catalogo.pantallas)
                let origen = conocido ? Reglas.origen(de: el, info: nil, pantallas: catalogo.pantallas).texto : tr("(se deduce de la cámara del vídeo)")
                print(tr("   origen: %@", origen))
                // Pistas que da el iPhone sin descargar el vídeo, para distinguir grabaciones
                // de pantalla de vídeos de otras apps.
                let f = video.file
                var pistas = [tr("píxeles: %@×%@", String(f.width), String(f.height)),
                              tr("duración: %@ s", String(format: "%.1f", f.duration)),
                              "uti: \(f.uti ?? "—")"]
                if let carpeta = f.parentFolder?.name { pistas.append(tr("carpeta: %@", carpeta)) }
                print("   " + pistas.joined(separator: " · "))
                // Cámara leída de la cabecera del vídeo (unos KB), sin descargarlo ni usar la caché.
                if !conocido {
                    if let info = await lectorSinCache.infoVideo(video) {
                        let origen = Reglas.origen(de: el, info: info, pantallas: catalogo.pantallas)
                        let ok = Reglas.motivoOrigen(origen, info: info, opciones: config.opciones) == nil
                        print(tr("   cámara (cabecera del vídeo): %@ / %@  · origen: %@  → %@",
                                 info.make ?? "—", info.model ?? "—", origen.texto,
                                 ok ? tr("pasa el filtro") : tr("se descartaría el elemento")))
                    } else {
                        print(tr("   cámara (cabecera del vídeo): no se pudo leer; se comprobaría al copiar"))
                    }
                }
            }
            for d in Reglas.clasificar(el, config.opciones) {
                let a = d.archivo
                let nombre = a.nombre.padding(toLength: 18, withPad: " ", startingAt: 0)
                let tam = formatoBytes(a.tamano).padding(toLength: 10, withPad: " ", startingAt: 0)
                let grupo = a.grupo.map { String($0.prefix(8)) } ?? "—"
                print("   \(d.conservar ? "✓" : "–") \(nombre) \(tam) \(formatoFecha(a.fecha))  " + tr("grupo %@", grupo) + "  \(d.tipo.texto)")
            }
        }
    }
}

/// Vuelca a un CSV todo lo que el iPhone expone por USB, sin agrupar ni filtrar,
/// para diagnosticar cómo nombra y fecha cada archivo.
@MainActor
public enum Volcado {
    @discardableResult
    public static func escribir(camara: ICCameraDevice) throws -> URL {
        var t = "\u{FEFF}" + tr("nombre;carpeta;origen;bytes;creacion;modificacion;uti;grupo") + "\n"
        var total = 0
        func fila(_ f: ICCameraFile, _ origen: String) {
            let campos = [
                f.name ?? "",
                f.parentFolder?.name ?? "",
                origen,
                String(Int64(f.fileSize)),
                formatoFecha(f.creationDate),
                formatoFecha(f.modificationDate),
                f.uti ?? "",
                f.groupUUID ?? "",
            ]
            t += campos.map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: ";") + "\n"
            total += 1
        }
        for item in camara.mediaFiles ?? [] {
            guard let f = item as? ICCameraFile else { continue }
            fila(f, tr("principal"))
            for s in f.sidecarFiles ?? [] {
                if let sf = s as? ICCameraFile { fila(sf, tr("auxiliar de %@", f.name ?? "?")) }
            }
        }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("catalogo-iphone.csv")
        try t.write(to: url, atomically: true, encoding: .utf8)
        print(tr("💾 %ld archivos volcados en %@", total, url.path))
        return url
    }
}
