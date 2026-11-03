import Foundation

/// Qué abarca una copia. Sustituye a las reglas fijas de la v0.1.
/// Por defecto: fotos y vídeos de la cámara de este iPhone, original + editada (como la v0.1,
/// que lo hacía con el modelo fijo «iPhone 17 Pro»).
/// Es `Codable` para guardarla en los perfiles; lee también los archivos de versiones anteriores.
public struct Opciones: Codable, Equatable, Sendable {

    public enum Periodo: Codable, Equatable, Sendable {
        /// Un rango sin fechas («el que indiques»): lo usan los perfiles como «Viaje».
        public static let rangoPorIndicar = Periodo.rango(desde: nil, hasta: nil)

        case todo
        /// Hoy y los n-1 días anteriores.
        case ultimosDias(Int)
        /// El mes natural anterior completo (el 2 de noviembre: del 1 al 31 de octubre).
        case mesAnterior
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
            case .mesAnterior:
                let inicioEsteMes = calendario.dateInterval(of: .month, for: ahora)?.start ?? calendario.startOfDay(for: ahora)
                let inicio = calendario.date(byAdding: .month, value: -1, to: inicioEsteMes) ?? inicioEsteMes
                return (inicio, inicioEsteMes.addingTimeInterval(-1))
            case .rango(let d, let h):
                return (d ?? .distantPast, h ?? .distantFuture)
            }
        }

        public func contiene(_ fecha: Date?, ahora: Date = Date()) -> Bool {
            guard let fecha else { return false }
            let (d, h) = limites(ahora: ahora)
            return fecha >= d && fecha <= h
        }

        /// «octubre de 2026»: el mes natural anterior, en el idioma en uso.
        public static func textoMesAnterior(ahora: Date = Date()) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: Idioma.actual)
            f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            return f.string(from: Periodo.mesAnterior.limites(ahora: ahora).desde)
        }

        public var descripcion: String {
            switch self {
            case .todo: return tr("en todo el iPhone")
            case .ultimosDias(let n): return tr("de los últimos %ld días", n)
            case .mesAnterior:
                return tr("del mes pasado (%@)", Periodo.textoMesAnterior())
            case .rango(nil, nil): return tr("en el rango de fechas que indiques")
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
    /// Con origen `.camara`: solo la cámara de este iPhone, deducida de sus fotos recientes
    /// al conectar (ver EsteIPhone). Mientras no se resuelve, `camaras` no se usa.
    public var esteIPhone = true
    /// Con origen `.camara` y sin `esteIPhone`: modelos aceptados (nil = cualquier cámara).
    public var camaras: [String]? = nil
    /// Modelo deducido de este iPhone (no se guarda: se vuelve a deducir en cada conexión).
    public var modeloEsteIPhone: String? = nil
    public var organizacion: Organizacion = .plana
    public var sha256 = false

    public init() {}

    // MARK: Lectura y escritura (compatible con los archivos de versiones anteriores)

    enum CodingKeys: String, CodingKey {
        case periodo, versiones, aae, videos, videoMaximo, videosLivePhoto, raw, origenes
        case esteIPhone, camaras, organizacion, sha256
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Opciones()
        periodo = try c.decodeIfPresent(Periodo.self, forKey: .periodo) ?? d.periodo
        versiones = try c.decodeIfPresent(Versiones.self, forKey: .versiones) ?? d.versiones
        aae = try c.decodeIfPresent(Bool.self, forKey: .aae) ?? d.aae
        videos = try c.decodeIfPresent(Bool.self, forKey: .videos) ?? d.videos
        videoMaximo = try c.decodeIfPresent(Int64.self, forKey: .videoMaximo)
        videosLivePhoto = try c.decodeIfPresent(Bool.self, forKey: .videosLivePhoto) ?? d.videosLivePhoto
        raw = try c.decodeIfPresent(ModoRAW.self, forKey: .raw) ?? d.raw
        origenes = try c.decodeIfPresent(Set<Origen>.self, forKey: .origenes) ?? d.origenes
        camaras = try c.decodeIfPresent([String].self, forKey: .camaras)
        // Archivos anteriores a «este iPhone»: se respeta la cámara que tenían guardada.
        esteIPhone = try c.decodeIfPresent(Bool.self, forKey: .esteIPhone) ?? false
        organizacion = try c.decodeIfPresent(Organizacion.self, forKey: .organizacion) ?? d.organizacion
        sha256 = try c.decodeIfPresent(Bool.self, forKey: .sha256) ?? d.sha256
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(periodo, forKey: .periodo)
        try c.encode(versiones, forKey: .versiones)
        try c.encode(aae, forKey: .aae)
        try c.encode(videos, forKey: .videos)
        try c.encodeIfPresent(videoMaximo, forKey: .videoMaximo)
        try c.encode(videosLivePhoto, forKey: .videosLivePhoto)
        try c.encode(raw, forKey: .raw)
        try c.encode(origenes, forKey: .origenes)
        try c.encode(esteIPhone, forKey: .esteIPhone)
        try c.encodeIfPresent(camaras, forKey: .camaras)
        try c.encode(organizacion, forKey: .organizacion)
        try c.encode(sha256, forKey: .sha256)
    }

    /// Las mismas opciones sin lo que se deduce al conectar (para comparar con un perfil).
    public var sinDeducciones: Opciones {
        var o = self
        o.modeloEsteIPhone = nil
        if o.esteIPhone { o.camaras = nil }
        return o
    }
}
