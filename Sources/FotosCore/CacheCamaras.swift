import Foundation

/// Carpetas de la herramienta fuera del proyecto.
public enum Rutas {
    /// ~/Library/Application Support/fotos-iphone/ (se crea si no existe).
    public static var soporte: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = base.appendingPathComponent("fotos-iphone", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Recuerda la cámara (fabricante, modelo, comentario) de cada archivo ya leído, para no
/// volver a pedírsela al iPhone. Leer la cámara de miles de fotos lleva minutos; con la caché,
/// la segunda simulación es casi inmediata.
/// Se guarda en ~/Library/Application Support/fotos-iphone/cache-camaras.json (nunca en el repositorio).
public final class CacheCamaras {
    private var tabla: [String: InfoCamara]
    private var cambios = 0
    public let url: URL?

    public static var porDefecto: URL? { Rutas.soporte?.appendingPathComponent("cache-camaras.json") }

    /// Con `url` nil la caché solo vive en memoria.
    public init(url: URL?) {
        self.url = url
        if let url, let datos = try? Data(contentsOf: url),
           let t = try? JSONDecoder().decode([String: InfoCamara].self, from: datos) {
            tabla = t
        } else {
            tabla = [:]
        }
    }

    public var cantidad: Int { tabla.count }

    public subscript(archivo: Archivo) -> InfoCamara? {
        get { tabla[archivo.identidad] }
        set {
            tabla[archivo.identidad] = newValue
            cambios += 1
        }
    }

    /// Guarda en disco si hubo cambios.
    public func guardar() {
        guard let url, cambios > 0 else { return }
        if let datos = try? JSONEncoder().encode(tabla) {
            try? datos.write(to: url, options: .atomic)
            cambios = 0
        }
    }
}
