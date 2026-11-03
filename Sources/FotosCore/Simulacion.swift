import Foundation

/// Lo que dice una simulación de cada archivo.
public struct ArchivoSimulado {
    public let archivo: Archivo
    public let tipo: TipoArchivo
    public let resultado: Resultado
    public let motivo: String

    public init(archivo: Archivo, tipo: TipoArchivo, resultado: Resultado, motivo: String) {
        self.archivo = archivo
        self.tipo = tipo
        self.resultado = resultado
        self.motivo = motivo
    }
}

/// Un elemento del carrete (foto, vídeo, Live Photo…) con lo que pasaría con cada uno de sus archivos.
public final class ElementoSimulado: Identifiable {
    /// Qué pasaría con el elemento en conjunto.
    public enum Categoria: Int, CaseIterable, Identifiable, Sendable {
        /// Se copia al menos uno de sus archivos (o se mueve dentro del destino).
        case seCopiara
        /// Lo que se conserva ya está en el destino.
        case yaCopiado
        /// No se copia ninguno de sus archivos.
        case descartado
        /// Error o no encontrado.
        case conError

        public var id: Int { rawValue }

        public var texto: String {
            switch self {
            case .seCopiara: return tr("Se copiarán")
            case .yaCopiado: return tr("Ya copiados")
            case .descartado: return tr("Descartados")
            case .conError: return tr("Con errores")
            }
        }
    }

    public let id: Int
    public let etiqueta: String
    public fileprivate(set) var archivos: [ArchivoSimulado] = []

    init(id: Int, etiqueta: String) {
        self.id = id
        self.etiqueta = etiqueta
    }

    public var categoria: Categoria {
        let resultados = Set(archivos.map(\.resultado))
        if !resultados.isDisjoint(with: [.seCopiaria, .seReubicaria, .copiado, .copiadoConAviso, .reubicado]) {
            return .seCopiara
        }
        if !resultados.isDisjoint(with: [.error, .noEncontrado]) || archivos.isEmpty { return .conError }
        if resultados.contains(.yaExistia) { return .yaCopiado }
        return .descartado
    }

    /// Por qué no se copia (el motivo del primer archivo descartado, o el del error).
    public var motivo: String? {
        switch categoria {
        case .descartado: return archivos.first { $0.resultado == .descartado }?.motivo
        case .conError: return archivos.first { $0.resultado == .error || $0.resultado == .noEncontrado }?.motivo
        default: return nil
        }
    }

    /// Bytes que se descargarían del iPhone (lo que se mueve dentro del destino no cuenta).
    public var bytesACopiar: Int64 {
        archivos.filter { $0.resultado == .seCopiaria }.reduce(Int64(0)) { $0 + $1.archivo.tamano }
    }

    /// El archivo que representa al elemento (para la miniatura): la foto original, si no el vídeo…
    public var principal: Archivo? {
        let orden: [TipoArchivo] = [.fotoOriginal, .videoOriginal, .fotoEditada, .videoEditado, .videoLivePhoto]
        for t in orden {
            if let a = archivos.first(where: { $0.tipo == t }) { return a.archivo }
        }
        return archivos.first?.archivo
    }

    /// Vídeo (no foto ni Live Photo).
    public var esVideo: Bool {
        !archivos.contains { $0.tipo == .fotoOriginal || $0.tipo == .fotoEditada }
            && archivos.contains { $0.tipo == .videoOriginal || $0.tipo == .videoEditado }
    }

    public var esLivePhoto: Bool {
        archivos.contains { $0.tipo == .videoLivePhoto || $0.tipo == .videoLivePhotoEditado }
    }

    public var fecha: Date? { principal?.fecha }
}

/// Resultado de una simulación agrupado por elemento. Se rellena con los eventos de la copia
/// (`empezar` con cada elemento, `agregar` con cada archivo).
public final class ResultadoSimulacion {
    public private(set) var elementos: [ElementoSimulado] = []
    private var porEtiqueta: [String: ElementoSimulado] = [:]
    private var actual: ElementoSimulado?

    public init() {}

    /// Empieza un elemento (si ya existía, se sigue con el mismo).
    public func empezar(_ etiqueta: String) {
        if let e = porEtiqueta[etiqueta] {
            actual = e
            return
        }
        let e = ElementoSimulado(id: elementos.count, etiqueta: etiqueta)
        elementos.append(e)
        porEtiqueta[etiqueta] = e
        actual = e
    }

    public func agregar(etiqueta: String, _ a: ArchivoSimulado) {
        if actual?.etiqueta != etiqueta { empezar(etiqueta) }
        actual?.archivos.append(a)
    }

    public func elementos(_ c: ElementoSimulado.Categoria) -> [ElementoSimulado] {
        elementos.filter { $0.categoria == c }
    }

    public func cantidad(_ c: ElementoSimulado.Categoria) -> Int {
        elementos.reduce(0) { $0 + ($1.categoria == c ? 1 : 0) }
    }

    /// Archivos que se descargarían del iPhone.
    public var archivosACopiar: Int {
        elementos.reduce(0) { $0 + $1.archivos.filter { $0.resultado == .seCopiaria }.count }
    }

    public var bytesACopiar: Int64 {
        elementos.reduce(Int64(0)) { $0 + $1.bytesACopiar }
    }

    /// Archivos ya copiados que se moverían a la carpeta que les toca.
    public var archivosAMover: Int {
        elementos.reduce(0) { $0 + $1.archivos.filter { $0.resultado == .seReubicaria }.count }
    }

    /// Por qué se descartan los elementos, de más a menos frecuente.
    public var motivosDeDescarte: [(motivo: String, elementos: Int)] {
        let porMotivo = Dictionary(grouping: elementos(.descartado), by: { $0.motivo ?? "" })
        return porMotivo.map { (motivo: $0.key, elementos: $0.value.count) }
            .sorted { $0.elementos != $1.elementos ? $0.elementos > $1.elementos : $0.motivo < $1.motivo }
    }
}
