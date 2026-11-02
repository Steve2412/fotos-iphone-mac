import Foundation

/// Qué es cada archivo dentro de su elemento.
public enum TipoArchivo: Equatable, Sendable {
    case fotoOriginal, fotoEditada
    case videoLivePhoto, videoLivePhotoEditado
    case videoOriginal, videoEditado
    case ajustes, datosLivePhoto, otro

    public var texto: String {
        switch self {
        case .fotoOriginal: return tr("foto original")
        case .fotoEditada: return tr("foto editada")
        case .videoLivePhoto: return tr("vídeo de Live Photo")
        case .videoLivePhotoEditado: return tr("vídeo de Live Photo editado")
        case .videoOriginal: return tr("vídeo original")
        case .videoEditado: return tr("vídeo editado")
        case .ajustes: return tr("ajustes de edición (.AAE)")
        case .datosLivePhoto: return tr("datos de edición de la Live Photo (.DAT)")
        case .otro: return tr("otro")
        }
    }
}

/// Por qué no se copia un archivo.
public enum Motivo: Equatable, Sendable {
    case componenteLivePhoto
    case acompanaVideoLivePhoto
    case tipoNoPrevisto(ext: String)
    case sinOriginal
    case origenNoElegido(Opciones.Origen)
    case otraCamara(camara: String, aceptadas: [String])
    case edicionNoElegida
    case originalSustituido
    case ajustesNoElegidos
    case videosExcluidos
    case videoDemasiadoGrande(limite: Int64)
    case rawExcluido
    case noEsRAW
    case sinVersionCopiada

    public var texto: String {
        switch self {
        case .componenteLivePhoto: return tr("componente de Live Photo")
        case .acompanaVideoLivePhoto: return tr("acompaña al vídeo de la Live Photo")
        case .tipoNoPrevisto(let ext): return tr("tipo de archivo no previsto (.%@)", ext)
        case .sinOriginal: return tr("el archivo original no está en el iPhone")
        case .origenNoElegido(let o): return tr("origen no elegido: %@", o.texto)
        case .otraCamara(let c, let a): return tr("tomado con «%@», no con %@", c, a.joined(separator: " / "))
        case .edicionNoElegida: return tr("solo se copian los originales")
        case .originalSustituido: return tr("se copia la versión editada en su lugar")
        case .ajustesNoElegidos: return tr("instrucciones de edición no elegidas")
        case .videosExcluidos: return tr("vídeos no elegidos")
        case .videoDemasiadoGrande(let l): return tr("vídeo mayor que el límite (%@)", formatoBytes(l))
        case .rawExcluido: return tr("RAW no elegido")
        case .noEsRAW: return tr("solo se copian fotos RAW")
        case .sinVersionCopiada: return tr("no se copia ninguna versión de este elemento")
        }
    }
}

public struct Decision {
    public let archivo: Archivo
    public let tipo: TipoArchivo
    /// nil = se copia.
    public let motivo: Motivo?
    /// Ruta dentro de la carpeta de destino, según la organización elegida.
    public let rutaRelativa: String

    public var conservar: Bool { motivo == nil }
}

public enum Reglas {

    /// Decide qué se copia de cada archivo de un elemento según las opciones.
    /// No mira el origen ni la cámara: eso necesita leer metadatos del iPhone (ver `motivoOrigen`).
    public static func clasificar(_ el: Elemento, _ op: Opciones) -> [Decision] {
        let esFoto = el.imagenOriginal != nil
        let esVideo = !esFoto && el.videoOriginal != nil
        let esRAW = el.imagenOriginal?.esRAW ?? false

        // Motivo que afecta a todo el elemento.
        var motivoElemento: Motivo?
        if op.raw == .solo && !esRAW {
            motivoElemento = .noEsRAW
        } else if esVideo && !op.videos {
            motivoElemento = .videosExcluidos
        }

        func tieneEdicion(_ clase: Clase) -> Bool {
            el.archivos.contains { !$0.esOriginal && $0.clase == clase }
        }
        func motivoVersion(_ a: Archivo) -> Motivo? {
            switch op.versiones {
            case .originales: return a.esOriginal ? nil : .edicionNoElegida
            case .final: return a.esOriginal && tieneEdicion(a.clase) ? .originalSustituido : nil
            case .originalYEditada: return nil
            }
        }
        func motivoTamano(_ a: Archivo) -> Motivo? {
            guard let max = op.videoMaximo, a.tamano > max else { return nil }
            return .videoDemasiadoGrande(limite: max)
        }
        let conAjustes = op.versiones == .originalYEditada && op.aae

        var decisiones = el.archivos.map { a -> Decision in
            let tipo: TipoArchivo
            var motivo: Motivo?
            switch a.clase {
            case .imagen:
                tipo = a.esOriginal ? .fotoOriginal : .fotoEditada
                motivo = (a.esRAW && op.raw == .excluir) ? .rawExcluido : motivoVersion(a)
            case .video where esFoto:
                tipo = a.esOriginal ? .videoLivePhoto : .videoLivePhotoEditado
                motivo = op.videosLivePhoto ? (motivoVersion(a) ?? motivoTamano(a)) : .componenteLivePhoto
            case .video:
                tipo = a.esOriginal ? .videoOriginal : .videoEditado
                motivo = motivoVersion(a) ?? motivoTamano(a)
            case .ajustes:
                tipo = .ajustes
                motivo = conAjustes ? nil : .ajustesNoElegidos
            case .otro where a.ext == "DAT" && esFoto:
                tipo = .datosLivePhoto
                motivo = (conAjustes && op.videosLivePhoto) ? nil : .acompanaVideoLivePhoto
            case .otro:
                tipo = .otro
                motivo = .tipoNoPrevisto(ext: a.ext)
            }
            if let m = motivoElemento { motivo = m }
            return Decision(archivo: a, tipo: tipo, motivo: motivo,
                            rutaRelativa: rutaRelativa(nombre: a.nombre, fecha: el.fecha, organizacion: op.organizacion))
        }

        // .AAE y .DAT solo tienen sentido junto a alguna foto o vídeo copiado.
        let copiaAlgo = decisiones.contains { $0.conservar && ($0.archivo.clase == .imagen || $0.archivo.clase == .video) }
        if !copiaAlgo {
            decisiones = decisiones.map { d in
                d.conservar ? Decision(archivo: d.archivo, tipo: d.tipo, motivo: .sinVersionCopiada, rutaRelativa: d.rutaRelativa) : d
            }
        }
        return decisiones.sorted { orden($0) < orden($1) }
    }

    private static func orden(_ d: Decision) -> Int {
        if d.archivo.esOriginal { return d.archivo.clase == .imagen || d.archivo.clase == .video ? 0 : 3 }
        return d.archivo.clase == .ajustes ? 2 : 1
    }

    /// ¿Hace falta leer los metadatos de cada elemento para saber su origen y su cámara?
    /// No, si se aceptan todos los orígenes y cualquier cámara.
    public static func necesitaMetadatos(_ op: Opciones) -> Bool {
        op.camaras != nil || op.origenes != Set(Opciones.Origen.allCases)
    }

    /// De dónde viene un elemento. `info` son los metadatos de su foto o vídeo original
    /// (nil si no se leyeron) y `pantallas`, las resoluciones de pantalla del catálogo.
    /// Criterio, comprobado con casos reales en iOS 26:
    ///  · IMG_… con Make o Model                         → cámara
    ///  · vídeo con la resolución de una pantalla        → grabación de pantalla
    ///    (iOS las entrega con nombre aleatorio, p. ej. WIOR2185.MP4 a 1206×2622)
    ///  · nombre que no es IMG_… (WhatsApp, Telegram…)    → otra app
    ///  · foto PNG o marcada «Screenshot»                → captura de pantalla
    ///  · el resto (JPG/MP4 sin datos de cámara)         → otra app
    public static func origen(de el: Elemento, info: InfoCamara?,
                              pantallas: Set<Resolucion> = Resolucion.pantallasConocidas) -> Opciones.Origen {
        if el.numero != nil, let info, info.tieneCamara { return .camara }
        if esGrabacionDePantalla(el, pantallas: pantallas) { return .grabacionPantalla }
        if el.numero == nil { return .otrasApps }
        if let img = el.imagenOriginal {
            let comentario = info?.comentario ?? ""
            if img.ext == "PNG" || comentario.localizedCaseInsensitiveContains("screenshot") { return .captura }
        }
        return .otrasApps
    }

    /// Un vídeo (que no es de Live Photo) con la resolución exacta de una pantalla de iPhone.
    /// Se sabe sin descargarlo: la cámara nunca graba a esas resoluciones.
    public static func esGrabacionDePantalla(_ el: Elemento, pantallas: Set<Resolucion>) -> Bool {
        guard el.imagenOriginal == nil, let r = el.videoOriginal?.resolucion else { return false }
        return pantallas.contains(r)
    }

    /// nil si el elemento entra; si no, el motivo para descartarlo entero.
    public static func motivoOrigen(_ origen: Opciones.Origen, info: InfoCamara?, opciones op: Opciones) -> Motivo? {
        guard op.origenes.contains(origen) else { return .origenNoElegido(origen) }
        guard origen == .camara, let aceptadas = op.camaras else { return nil }
        if let model = info?.model {
            let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if aceptadas.contains(where: { $0.caseInsensitiveCompare(m) == .orderedSame }) { return nil }
        }
        let camara = [info?.make, info?.model].compactMap { $0 }.joined(separator: " ")
        return .otraCamara(camara: camara, aceptadas: aceptadas)
    }

    private static let calendario: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    /// Ruta dentro del destino. Todos los archivos de un elemento van a la carpeta
    /// de su fecha de captura, para que la versión editada no acabe en otro mes.
    public static func rutaRelativa(nombre: String, fecha: Date?, organizacion: Opciones.Organizacion) -> String {
        if organizacion == .plana { return nombre }
        guard let fecha else { return "sin-fecha/\(nombre)" }
        let c = calendario.dateComponents([.year, .month, .day], from: fecha)
        let anio = String(format: "%04d", c.year ?? 0)
        let mes = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        let dia = mes + String(format: "-%02d", c.day ?? 0)
        switch organizacion {
        case .plana: return nombre
        case .anioMes: return "\(anio)/\(mes)/\(nombre)"
        case .dia: return "\(anio)/\(mes)/\(dia)/\(nombre)"
        }
    }
}

/// Lo que se sabe de la cámara de un elemento.
public struct InfoCamara: Equatable, Sendable {
    public var make: String?
    public var model: String?
    /// Comentario EXIF (UserComment): iOS pone «Screenshot» en las capturas de pantalla.
    public var comentario: String?

    public init(make: String? = nil, model: String? = nil, comentario: String? = nil) {
        self.make = make
        self.model = model
        self.comentario = comentario
    }

    public var tieneCamara: Bool { make != nil || model != nil }
}

public enum DatosCamara {
    /// Fabricante, modelo y comentario a partir del diccionario de metadatos de una foto.
    public static func info(en dic: [AnyHashable: Any]) -> InfoCamara {
        let (make, model) = makeModel(en: dic)
        let exif = dic["{Exif}"] as? [AnyHashable: Any]
        return InfoCamara(make: make, model: model, comentario: exif?["UserComment"] as? String)
    }

    /// Busca Make/Model en el diccionario de metadatos (primero en {TIFF}).
    public static func makeModel(en dic: [AnyHashable: Any]) -> (make: String?, model: String?) {
        if let tiff = dic["{TIFF}"] as? [AnyHashable: Any] {
            let make = tiff["Make"] as? String
            let model = tiff["Model"] as? String
            if make != nil || model != nil { return (make, model) }
        }
        var make: String?
        var model: String?
        func recorrer(_ d: [AnyHashable: Any]) {
            for (k, v) in d {
                if let clave = k as? String, let texto = v as? String {
                    if clave == "Make", make == nil { make = texto }
                    if clave == "Model", model == nil { model = texto }
                }
                if let sub = v as? [AnyHashable: Any] { recorrer(sub) }
            }
        }
        recorrer(dic)
        return (make, model)
    }
}
