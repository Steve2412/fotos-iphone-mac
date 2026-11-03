import Foundation

/// Registro de lo copiado, guardado en el destino (`.fotos-iphone/manifiesto.json`).
///
/// Para cada archivo del iPhone apunta dónde quedó en el destino. Así:
///  · al reanudar se reconoce lo ya copiado aunque se renombrara («IMG_0001 (2).HEIC»)
///    o se cambiara la organización de carpetas;
///  · el borrado sabe exactamente qué está respaldado y dónde.
/// Contiene nombres y fechas de tus fotos: vive en tu carpeta de fotos, nunca en el repositorio.
public struct Manifiesto: Codable, Equatable {
    public struct Entrada: Codable, Equatable {
        /// Ruta relativa a la carpeta de destino.
        public var ruta: String
        public var tamano: Int64
        /// Elemento al que pertenece (IMG_1234, THQV8599…).
        public var elemento: String
        public var copiado: Date
        public var sha256: String?
    }

    public var version = 1
    /// Clave: `Archivo.identidad`.
    public var entradas: [String: Entrada] = [:]

    public init() {}

    public static func url(en destino: URL) -> URL {
        destino.appendingPathComponent(".fotos-iphone", isDirectory: true)
            .appendingPathComponent("manifiesto.json")
    }

    /// Lee el manifiesto del destino (vacío si aún no existe).
    public static func leer(en destino: URL) -> Manifiesto {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let datos = try? Data(contentsOf: url(en: destino)),
              let m = try? d.decode(Manifiesto.self, from: datos) else { return Manifiesto() }
        return m
    }

    public func escribir(en destino: URL) throws {
        let url = Manifiesto.url(en: destino)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }

    public mutating func registrar(_ a: Archivo, ruta: String, elemento: String, sha256: String? = nil, fecha: Date = Date()) {
        // Segundos enteros: el formato ISO 8601 del archivo no guarda fracciones.
        let copiado = Date(timeIntervalSince1970: fecha.timeIntervalSince1970.rounded(.down))
        entradas[a.identidad] = Entrada(ruta: ruta, tamano: a.tamano, elemento: elemento, copiado: copiado,
                                        sha256: (sha256?.isEmpty ?? true) ? nil : sha256)
    }

    /// Dónde se copió este archivo del iPhone, si consta.
    public func ruta(de a: Archivo) -> String? { entradas[a.identidad]?.ruta }
}
