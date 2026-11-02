import Foundation
import ImageCaptureCore
import FotosCore

/// Puente entre el catálogo real del iPhone (ImageCaptureCore) y el modelo puro de FotosCore.

extension Archivo {
    convenience init(_ f: ICCameraFile) {
        self.init(nombre: f.name ?? tr("(sin nombre)"), tamano: Int64(f.fileSize),
                  fecha: f.creationDate, grupo: f.groupUUID,
                  ancho: f.width, alto: f.height, origen: f)
    }

    /// El archivo real en el iPhone.
    var file: ICCameraFile { origen as! ICCameraFile }
}

extension Catalogo {
    /// Lee el catálogo del iPhone: los archivos principales y sus compañeros (sidecars).
    public convenience init(camara: ICCameraDevice) {
        var lista: [Archivo] = []
        for item in camara.mediaFiles ?? [] {
            guard let f = item as? ICCameraFile else { continue }
            lista.append(Archivo(f))
            for s in f.sidecarFiles ?? [] {
                if let sf = s as? ICCameraFile { lista.append(Archivo(sf)) }
            }
        }
        self.init(archivos: lista)
    }
}
