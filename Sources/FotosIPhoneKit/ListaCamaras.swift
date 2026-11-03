import Foundation
import ImageCaptureCore
import FotosCore

/// Cuántos elementos hay de una cámara o de un origen.
public struct ConteoCamara {
    /// «iPhone 17 Pro», «EOS R6 — Canon», «captura de pantalla»…
    public let etiqueta: String
    /// Modelo tal como se usa en --modelo (nil si no es una cámara).
    public let modelo: String?
    public var fotos = 0
    public var videos = 0
    public var total: Int { fotos + videos }
}

/// `--camaras`: cuenta los elementos por cámara y origen en el periodo elegido
/// (o en todo el iPhone). El asistente lo usa para ofrecer los modelos.
@MainActor
public final class ListaCamaras {
    let config: Configuracion
    let catalogo: Catalogo

    public init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
    }

    public func ejecutar() async {
        let conteos = await contar(en: config.opciones.periodo)
        print(tr("\n📷 Cámaras y orígenes:"))
        for c in conteos {
            print(tr("   %@  ·  %ld fotos · %ld vídeos", c.etiqueta, c.fotos, c.videos))
        }
        print(tr("\nPara elegir cámaras: --modelo \"iPhone 17 Pro\" (se puede repetir) o --cualquier-camara."))
    }

    /// Lee la cámara de cada elemento del periodo (con la caché, la segunda vez es rápido).
    public func contar(en periodo: Opciones.Periodo) async -> [ConteoCamara] {
        let elementos = catalogo.elementos(en: periodo)
        let lector = LectorCamara()
        print(tr("📷 Leyendo la cámara de %ld elementos %@ (lo leído se recuerda para la próxima vez)…",
                 elementos.count, periodo.descripcion))

        var conteos: [String: ConteoCamara] = [:]
        for (i, el) in elementos.enumerated() {
            if (i + 1) % 200 == 0 {
                print(tr("   … %ld/%ld", i + 1, elementos.count))
                lector.guardar()
            }
            let clave: (etiqueta: String, modelo: String?)
            if el.numero == nil || Reglas.esGrabacionDePantalla(el, pantallas: catalogo.pantallas) {
                clave = (Reglas.origen(de: el, info: nil, pantallas: catalogo.pantallas).texto, nil)
            } else if let img = el.imagenOriginal {
                let info = await lector.infoFoto(img)
                clave = etiqueta(el, info)
            } else if let video = el.videoOriginal {
                if let info = await lector.infoVideo(video) {
                    clave = etiqueta(el, info)
                } else {
                    clave = (tr("vídeo (no se pudo leer la cámara)"), nil)
                }
            } else {
                continue
            }
            var c = conteos[clave.etiqueta] ?? ConteoCamara(etiqueta: clave.etiqueta, modelo: clave.modelo)
            if el.imagenOriginal != nil { c.fotos += 1 } else { c.videos += 1 }
            conteos[clave.etiqueta] = c
        }
        lector.guardar()
        if lector.videosSinLeer > 0 {
            print(tr("   ⚠️  %ld vídeos sin cabecera legible: su cámara se comprueba al copiar.", lector.videosSinLeer))
        }
        return conteos.values.sorted { $0.total != $1.total ? $0.total > $1.total : $0.etiqueta < $1.etiqueta }
    }

    /// «iPhone 17 Pro» (o «EOS R6 — Canon» si no es de Apple) para cámaras; el origen para lo demás.
    private func etiqueta(_ el: Elemento, _ info: InfoCamara) -> (etiqueta: String, modelo: String?) {
        let origen = Reglas.origen(de: el, info: info, pantallas: catalogo.pantallas)
        guard origen == .camara else { return (origen.texto, nil) }
        guard let modelo = info.model else { return (tr("modelo desconocido"), nil) }
        if let make = info.make, !make.localizedCaseInsensitiveContains("Apple") {
            return ("\(modelo) — \(make)", modelo)
        }
        return (modelo, modelo)
    }
}
