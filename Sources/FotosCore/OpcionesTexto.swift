import Foundation

// Textos para mostrar las opciones y lectura de sus valores desde Terminal
// (se aceptan en español y en inglés, con o sin tildes).

extension Opciones.Versiones {
    public var texto: String {
        switch self {
        case .originales: return tr("solo originales")
        case .final: return tr("versión final (la editada si existe)")
        case .originalYEditada: return tr("original + editada")
        }
    }

    public init?(texto: String) {
        switch normalizar(texto) {
        case "originales", "original", "originals": self = .originales
        case "final": self = .final
        case "ambas", "ambos", "todas", "both", "all", "original+editada", "original+edited": self = .originalYEditada
        default: return nil
        }
    }
}

extension Opciones.ModoRAW {
    public var texto: String {
        switch self {
        case .incluir: return tr("incluir")
        case .excluir: return tr("excluir")
        case .solo: return tr("solo RAW")
        }
    }

    public init?(texto: String) {
        switch normalizar(texto) {
        case "incluir", "si", "include", "yes": self = .incluir
        case "excluir", "no", "exclude": self = .excluir
        case "solo", "only": self = .solo
        default: return nil
        }
    }
}

extension Opciones.Organizacion {
    public var texto: String {
        switch self {
        case .plana: return tr("carpeta única")
        case .anioMes: return tr("por año y mes (2026/2026-10/)")
        case .dia: return tr("por día (2026/2026-10/2026-10-20/)")
        }
    }

    public init?(texto: String) {
        switch normalizar(texto) {
        case "plana", "unica", "flat", "single": self = .plana
        case "mes", "anio-mes", "ano-mes", "month", "year-month": self = .anioMes
        case "dia", "day": self = .dia
        default: return nil
        }
    }
}

extension Opciones.Origen {
    public init?(texto: String) {
        switch normalizar(texto) {
        case "camara", "camaras", "camera", "cameras": self = .camara
        case "captura", "capturas", "screenshot", "screenshots": self = .captura
        case "grabacion", "grabaciones", "recording", "recordings": self = .grabacionPantalla
        case "apps", "app", "otras", "otras-apps", "other", "others": self = .otrasApps
        default: return nil
        }
    }

    /// Lista separada por comas («camara,capturas») o «todo» / «all».
    public static func conjunto(_ texto: String) -> Set<Opciones.Origen>? {
        let n = normalizar(texto)
        if n == "todo" || n == "todos" || n == "all" { return Set(allCases) }
        var r = Set<Opciones.Origen>()
        for parte in n.split(separator: ",") {
            guard let o = Opciones.Origen(texto: String(parte)) else { return nil }
            r.insert(o)
        }
        return r.isEmpty ? nil : r
    }
}

extension Opciones {
    /// Tamaño escrito a mano: «2GB», «500 MB», «1.5G», «800m». Sin unidad se entiende MB.
    /// Unidades de 1000, como el Finder.
    public static func bytes(_ texto: String) -> Int64? {
        let t = normalizar(texto).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        let unidades: [(String, Double)] = [("tb", 1e12), ("t", 1e12), ("gb", 1e9), ("g", 1e9),
                                            ("mb", 1e6), ("m", 1e6), ("kb", 1e3), ("k", 1e3)]
        for (sufijo, factor) in unidades where t.hasSuffix(sufijo) {
            guard let n = Double(t.dropLast(sufijo.count)), n > 0 else { return nil }
            return Int64(n * factor)
        }
        guard let n = Double(t), n > 0 else { return nil }
        return Int64(n * 1e6)
    }

    /// Una línea por opción, para mostrar antes de simular o copiar.
    public var resumen: [String] {
        let si = tr("sí"), no = tr("no")
        var l: [String] = []
        l.append(tr("Periodo: %@", periodo.descripcion))
        let nombres = Opciones.Origen.allCases.filter(origenes.contains).map(\.texto)
        l.append(tr("Orígenes: %@", nombres.joined(separator: ", ")))
        if origenes.contains(.camara) {
            l.append(tr("Cámaras: %@", camaras?.joined(separator: ", ") ?? tr("cualquiera")))
        }
        l.append(tr("Versiones: %@", versiones.texto))
        if versiones == .originalYEditada {
            l.append(tr("Instrucciones de edición (.AAE): %@", aae ? si : no))
        }
        let textoVideos = videos ? (videoMaximo.map { tr("sí, hasta %@", formatoBytes($0)) } ?? si) : no
        l.append(tr("Vídeos: %@", textoVideos))
        l.append(tr("Vídeos de las Live Photos: %@", videosLivePhoto ? si : no))
        l.append(tr("RAW: %@", raw.texto))
        l.append(tr("Organización: %@", organizacion.texto))
        if sha256 { l.append(tr("Huella SHA-256: sí")) }
        return l
    }
}

/// Minúsculas, sin tildes y sin espacios a los lados.
func normalizar(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        .trimmingCharacters(in: .whitespaces)
}
