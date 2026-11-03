import Foundation
import CoreGraphics
import ImageIO
import ImageCaptureCore
import FotosCore

/// Miniaturas de los archivos del iPhone, pedidas por cable (unos KB cada una, sin descargar
/// el archivo). Se guardan en memoria mientras dura la conexión.
@MainActor
public final class Miniaturas {
    private let cache = NSCache<NSString, CGImage>()
    /// Peticiones en curso: el iPhone las atiende de pocas en pocas.
    private var enCurso = 0
    private let maximo = 4

    public init() {
        cache.countLimit = 2_000
    }

    /// Miniatura de `archivo` con su lado mayor de hasta `lado` píxeles (nil si el iPhone no la da).
    /// Si la tarea se cancela mientras espera turno (la celda salió de la pantalla), no se pide.
    public func imagen(de archivo: Archivo, lado: Int = 240) async -> CGImage? {
        let clave = archivo.identidad as NSString
        if let img = cache.object(forKey: clave) { return img }
        while enCurso >= maximo {
            if Task.isCancelled { return nil }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        if Task.isCancelled { return nil }
        if let img = cache.object(forKey: clave) { return img }
        enCurso += 1
        defer { enCurso -= 1 }
        guard let datos = await archivo.file.datosMiniatura() else { return nil }
        guard let img = Self.reducir(datos, lado: lado) else { return nil }
        cache.setObject(img, forKey: clave)
        return img
    }

    public func vaciar() {
        cache.removeAllObjects()
    }

    /// Decodifica y reduce la miniatura, girándola según su orientación EXIF.
    nonisolated static func reducir(_ datos: Data, lado: Int) -> CGImage? {
        guard let fuente = CGImageSourceCreateWithData(datos as CFData, nil) else { return nil }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lado,
        ]
        return CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary)
    }
}

extension ICCameraFile {
    /// Miniatura (normalmente JPEG) tal como la da el iPhone.
    func datosMiniatura() async -> Data? {
        await withCheckedContinuation { cont in
            requestThumbnailData(options: [:]) { datos, _ in
                cont.resume(returning: datos)
            }
        }
    }
}
