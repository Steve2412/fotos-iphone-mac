import Foundation
import ImageCaptureCore
import FotosCore

/// `--camaras`: cuenta los elementos por cámara y origen en el periodo elegido
/// (o en todo el iPhone), para saber qué modelos elegir con --modelo.
@MainActor
public final class ListaCamaras {
    let config: Configuracion
    let catalogo: Catalogo

    public init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
    }

    public func ejecutar() async {
        let op = config.opciones
        let elementos = catalogo.elementos(en: op.periodo)
        let lector = LectorCamara()
        print(tr("📷 Leyendo la cámara de %ld elementos %@ (lo leído se recuerda para la próxima vez)…",
                 elementos.count, op.periodo.descripcion))

        var fotos: [String: Int] = [:]
        var videos: [String: Int] = [:]
        for (i, el) in elementos.enumerated() {
            if (i + 1) % 200 == 0 {
                print(tr("   … %ld/%ld", i + 1, elementos.count))
                lector.guardar()
            }
            let clave: String
            if el.numero == nil || Reglas.esGrabacionDePantalla(el, pantallas: catalogo.pantallas) {
                clave = Reglas.origen(de: el, info: nil, pantallas: catalogo.pantallas).texto
            } else if let img = el.imagenOriginal {
                let info = await lector.infoFoto(img)
                clave = etiqueta(el, info)
            } else if let video = el.videoOriginal {
                if let info = await lector.infoVideo(video) {
                    clave = etiqueta(el, info)
                } else {
                    clave = tr("vídeo (no se pudo leer la cámara)")
                }
            } else {
                continue
            }
            if el.imagenOriginal != nil { fotos[clave, default: 0] += 1 } else { videos[clave, default: 0] += 1 }
        }
        lector.guardar()

        let claves = Set(fotos.keys).union(videos.keys)
            .sorted { (fotos[$0, default: 0] + videos[$0, default: 0]) > (fotos[$1, default: 0] + videos[$1, default: 0]) }
        print(tr("\n📷 Cámaras y orígenes:"))
        for c in claves {
            print(tr("   %@  ·  %ld fotos · %ld vídeos", c, fotos[c, default: 0], videos[c, default: 0]))
        }
        if lector.videosSinLeer > 0 {
            print(tr("   ⚠️  %ld vídeos sin cabecera legible: su cámara se comprueba al copiar.", lector.videosSinLeer))
        }
        print(tr("\nPara elegir cámaras: --modelo \"iPhone 17 Pro\" (se puede repetir) o --cualquier-camara."))
    }

    /// «iPhone 17 Pro» (o «EOS R6 — Canon» si no es de Apple) para cámaras; el origen para lo demás.
    private func etiqueta(_ el: Elemento, _ info: InfoCamara) -> String {
        let origen = Reglas.origen(de: el, info: info, pantallas: catalogo.pantallas)
        guard origen == .camara else { return origen.texto }
        let modelo = info.model ?? tr("modelo desconocido")
        if let make = info.make, !make.localizedCaseInsensitiveContains("Apple") {
            return "\(modelo) — \(make)"
        }
        return modelo
    }
}
