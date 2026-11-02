import Foundation

/// Qué abarca una copia. Sustituye a las reglas fijas de la v0.1.
/// Los valores por defecto reproducen exactamente el comportamiento de la v0.1.
/// Es `Codable` para guardarla en los perfiles.
public struct Opciones: Codable, Equatable, Sendable {

    public enum Periodo: Codable, Equatable, Sendable {
        case todo
        /// Hoy y los n-1 días anteriores.
        case ultimosDias(Int)
        /// Límites incluidos. `hasta` es el último instante que entra (p. ej. 23:59:59 de ese día).
        case rango(desde: Date?, hasta: Date?)

        public func limites(ahora: Date = Date(), calendario: Calendar = .current) -> (desde: Date, hasta: Date) {
            switch self {
            case .todo:
                return (.distantPast, .distantFuture)
            case .ultimosDias(let n):
                let hoy = calendario.startOfDay(for: ahora)
                let desde = calendario.date(byAdding: .day, value: -(max(n, 1) - 1), to: hoy) ?? hoy
                return (desde, .distantFuture)
            case .rango(let d, let h):
                return (d ?? .distantPast, h ?? .distantFuture)
            }
        }

        public func contiene(_ fecha: Date?, ahora: Date = Date()) -> Bool {
            guard let fecha else { return false }
            let (d, h) = limites(ahora: ahora)
            return fecha >= d && fecha <= h
        }

        public var descripcion: String {
            switch self {
            case .todo: return tr("en todo el iPhone")
            case .ultimosDias(let n): return tr("de los últimos %ld días", n)
            case .rango(let d, let h): return tr("entre %@ y %@", formatoFecha(d), formatoFecha(h))
            }
        }
    }

    /// Qué versión se copia de cada foto o vídeo.
    public enum Versiones: String, Codable, CaseIterable, Sendable {
        /// Solo el original, tal como salió de la cámara.
        case originales
        /// La versión editada si existe; si no, el original (lo que ves en Fotos).
        case final
        /// El original y la versión editada (comportamiento de la v0.1).
        case originalYEditada
    }

    /// De dónde viene cada foto o vídeo del carrete.
    public enum Origen: String, Codable, CaseIterable, Sendable {
        /// Con datos de cámara (Make/Model): iPhone, otras cámaras.
        case camara
        /// Capturas de pantalla.
        case captura
        /// Grabaciones de pantalla.
        case grabacionPantalla
        /// Imágenes y vídeos de otras apps o descargados (WhatsApp, Safari…).
        case otrasApps

        public var texto: String {
            switch self {
            case .camara: return tr("foto o vídeo de cámara")
            case .captura: return tr("captura de pantalla")
            case .grabacionPantalla: return tr("grabación de pantalla")
            case .otrasApps: return tr("de otra app o descargado")
            }
        }
    }

    public enum ModoRAW: String, Codable, CaseIterable, Sendable {
        case incluir, excluir, solo
    }

    public enum Organizacion: String, Codable, CaseIterable, Sendable {
        /// Todo en la carpeta de destino.
        case plana
        /// destino/2026/2026-10/
        case anioMes
        /// destino/2026/2026-10/2026-10-20/
        case dia
    }

    public var periodo: Periodo = .todo
    public var versiones: Versiones = .originalYEditada
    /// Instrucciones de edición (.AAE). Solo cuentan con `versiones == .originalYEditada`.
    public var aae = true
    public var videos = true
    /// Tamaño máximo de cada vídeo en bytes (nil = sin límite).
    public var videoMaximo: Int64? = nil
    public var videosLivePhoto = false
    public var raw: ModoRAW = .incluir
    /// Orígenes que se copian.
    public var origenes: Set<Origen> = [.camara]
    /// Con origen `.camara`: modelos aceptados (nil = cualquier cámara).
    public var camaras: [String]? = ["iPhone 17 Pro"]
    public var organizacion: Organizacion = .plana
    public var sha256 = false

    public init() {}
}
