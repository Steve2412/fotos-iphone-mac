import Foundation

public enum Clase: Sendable { case imagen, video, ajustes, otro }

/// Un archivo tal como lo muestra el iPhone por USB.
/// No depende de ImageCaptureCore: `origen` guarda el objeto real (ICCameraFile)
/// para el módulo que copia; las reglas no lo usan, y en las pruebas es nil.
public final class Archivo {
    public let nombre: String
    public let ext: String
    /// Número del contador de la cámara: IMG_1234 → 1234.
    public let numero: Int?
    /// "" para el original, "E" para la versión editada (IMG_E1234), "O" y "A" para auxiliares
    /// de la edición (IMG_O1234.AAE, IMG_A1234.DAT).
    public let marca: String
    public let clase: Clase
    public let tamano: Int64
    public let fecha: Date?
    public let grupo: String?
    /// Resolución en píxeles que informa el iPhone sin descargar el archivo (0 si no la da).
    public let ancho: Int
    public let alto: Int
    public let origen: AnyObject?

    public var esOriginal: Bool { marca.isEmpty && clase != .ajustes }
    public var esRAW: Bool { ext == "DNG" }
    public var resolucion: Resolucion? { ancho > 0 && alto > 0 ? Resolucion(ancho, alto) : nil }

    public init(nombre: String, tamano: Int64, fecha: Date?, grupo: String?,
                ancho: Int = 0, alto: Int = 0, origen: AnyObject? = nil) {
        self.nombre = nombre
        self.tamano = tamano
        self.fecha = fecha
        self.grupo = (grupo?.isEmpty ?? true) ? nil : grupo
        self.ancho = ancho
        self.alto = alto
        self.origen = origen
        ext = (nombre as NSString).pathExtension.uppercased()
        let partes = Archivo.analizar(nombre)
        numero = partes?.numero
        marca = partes?.marca ?? ""
        clase = Archivo.clase(de: ext)
    }

    static let extImagen: Set<String> = ["HEIC", "HEIF", "JPG", "JPEG", "DNG", "PNG", "TIF", "TIFF", "GIF", "WEBP"]
    static let extVideo: Set<String> = ["MOV", "MP4", "M4V"]

    static func clase(de ext: String) -> Clase {
        if extImagen.contains(ext) { return .imagen }
        if extVideo.contains(ext) { return .video }
        if ext == "AAE" { return .ajustes }
        return .otro
    }

    private static let patron = try! NSRegularExpression(
        pattern: #"^[A-Za-z]+_([EOAeoa]?)(\d{4,5})(?:\s*\(\d+\))?\.[A-Za-z0-9]+$"#
    )

    static func analizar(_ nombre: String) -> (marca: String, numero: Int)? {
        let rango = NSRange(nombre.startIndex..., in: nombre)
        guard let m = patron.firstMatch(in: nombre, range: rango),
              let rMarca = Range(m.range(at: 1), in: nombre),
              let rNumero = Range(m.range(at: 2), in: nombre),
              let n = Int(nombre[rNumero])
        else { return nil }
        return (String(nombre[rMarca]).uppercased(), n)
    }
}

/// Resolución sin orientación: 1206×2622 y 2622×1206 son la misma.
public struct Resolucion: Hashable, Sendable, CustomStringConvertible {
    public let corto: Int
    public let largo: Int

    public init(_ a: Int, _ b: Int) {
        corto = min(a, b)
        largo = max(a, b)
    }

    public var description: String { "\(corto)×\(largo)" }

    /// Proporción de pantalla de iPhone moderno (≈ 19,5:9) y tamaño de pantalla real.
    /// Sirve para no tomar por pantalla un PNG cualquiera guardado de otra app.
    public var pareceDePantalla: Bool {
        let p = Double(largo) / Double(corto)
        return corto >= 1000 && p >= 2.0 && p <= 2.3
    }

    /// Pantallas de iPhone (píxeles reales) desde el iPhone X. Se suman a las que se
    /// deducen de las capturas del catálogo, por si hay grabaciones hechas con otro iPhone.
    public static let pantallasConocidas: Set<Resolucion> = [
        Resolucion(1125, 2436), // X, XS, 11 Pro
        Resolucion(1242, 2688), // XS Max, 11 Pro Max
        Resolucion(1080, 2340), // 12 mini, 13 mini
        Resolucion(1170, 2532), // 12, 12 Pro, 13, 13 Pro, 14
        Resolucion(1284, 2778), // 12 Pro Max, 13 Pro Max, 14 Plus
        Resolucion(1179, 2556), // 14 Pro, 15, 15 Pro, 16
        Resolucion(1290, 2796), // 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus
        Resolucion(1206, 2622), // 16 Pro, 17, 17 Pro
        Resolucion(1320, 2868), // 16 Pro Max, 17 Pro Max
        Resolucion(1260, 2736), // Air
    ]
}

/// Un elemento de la fototeca: el original y todo lo que cuelga de él
/// (versión editada, .AAE, vídeo de la Live Photo…).
public final class Elemento {
    /// Número del contador (IMG_1234 → 1234); nil para archivos de otras apps (THQV8599.JPG).
    public let numero: Int?
    /// Nombre corto para mostrar: «IMG_1234» o «THQV8599».
    public let etiqueta: String
    public private(set) var archivos: [Archivo] = []

    init(numero: Int?, etiqueta: String) {
        self.numero = numero
        self.etiqueta = etiqueta
    }

    func agregar(_ a: Archivo) { archivos.append(a) }

    public var fecha: Date? {
        archivos.filter(\.esOriginal).compactMap(\.fecha).min() ?? archivos.compactMap(\.fecha).min()
    }
    /// Fecha más reciente de cualquiera de sus archivos (una edición la actualiza).
    public var ultimaActividad: Date? { archivos.compactMap(\.fecha).max() }
    public var imagenOriginal: Archivo? { archivos.first { $0.esOriginal && $0.clase == .imagen } }
    public var videoOriginal: Archivo? { archivos.first { $0.esOriginal && $0.clase == .video } }
    var grupos: Set<String> { Set(archivos.compactMap(\.grupo)) }

    public var descripcion: String {
        if imagenOriginal != nil { return tr("foto") }
        if videoOriginal != nil { return tr("vídeo") }
        return tr("sin original")
    }
}
