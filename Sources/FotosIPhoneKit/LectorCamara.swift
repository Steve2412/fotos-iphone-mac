import Foundation
import ImageCaptureCore
import FotosCore

extension ICCameraFile {
    /// Lee `cantidad` bytes desde `desde` sin descargar el archivo (lectura parcial por USB).
    @MainActor
    func leerBytes(desde: Int64, cantidad: Int64) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            requestReadData(atOffset: off_t(desde), length: off_t(cantidad)) { datos, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: datos ?? Data())
                }
            }
        }
    }
}

/// Lee la cámara (fabricante y modelo) de fotos y vídeos del iPhone, recordando lo leído
/// en la caché de ~/Library/Application Support/fotos-iphone/.
///  · Fotos: metadatos que da el iPhone (EXIF), sin descargar.
///  · Vídeos: solo la cabecera del vídeo (átomo moov, unos KB), sin descargar el vídeo.
@MainActor
public final class LectorCamara {
    private let cache: CacheCamaras?
    /// Vídeos cuya cabecera no se pudo leer (para avisar al final).
    public private(set) var videosSinLeer = 0

    public init(usarCache: Bool = true) {
        cache = usarCache ? CacheCamaras(url: CacheCamaras.porDefecto) : nil
    }

    public func infoFoto(_ a: Archivo) async -> InfoCamara {
        if let c = cache?[a] { return c }
        let dic = (try? await a.file.leerMetadatos()) ?? [:]
        let info = DatosCamara.info(en: dic)
        if !dic.isEmpty { cache?[a] = info }   // un fallo de lectura no se recuerda
        return info
    }

    /// nil si no se pudo leer la cabecera (el vídeo habría que descargarlo para saberlo).
    func infoVideo(_ a: Archivo) async -> InfoCamara? {
        if let c = cache?[a] { return c }
        let file = a.file
        do {
            let moov = try await QuickTime.moov(total: a.tamano) { desde, cantidad in
                try await file.leerBytes(desde: desde, cantidad: cantidad)
            }
            guard let moov else {
                videosSinLeer += 1
                return nil
            }
            let info = QuickTime.camara(enMoov: moov)
            cache?[a] = info
            return info
        } catch {
            videosSinLeer += 1
            return nil
        }
    }

    /// Recuerda lo leído de un vídeo ya descargado.
    func recordar(_ a: Archivo, _ info: InfoCamara) {
        cache?[a] = info
    }

    public func guardar() {
        cache?.guardar()
    }
}
