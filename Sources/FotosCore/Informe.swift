import Foundation

/// Qué pasó con cada archivo.
public enum Resultado: Sendable {
    case copiado, copiadoConAviso, yaExistia, seCopiaria, descartado, error, noEncontrado

    public var texto: String {
        switch self {
        case .copiado: return tr("copiado")
        case .copiadoConAviso: return tr("copiado con aviso")
        case .yaExistia: return tr("ya existía")
        case .seCopiaria: return tr("se copiaría")
        case .descartado: return tr("descartado")
        case .error: return tr("error")
        case .noEncontrado: return tr("no encontrado")
        }
    }

    public var icono: String {
        switch self {
        case .copiado, .yaExistia, .seCopiaria: return "✓"
        case .copiadoConAviso: return "⚠"
        case .descartado: return "–"
        case .error, .noEncontrado: return "✗"
        }
    }

    /// Cuenta para el volumen copiado (o a copiar).
    var suma: Bool { self == .copiado || self == .copiadoConAviso || self == .seCopiaria }
}

/// Resultado de cada archivo, que se guarda como informe.csv.
public final class Informe {
    struct Fila {
        let entrada, archivo, tipo: String
        let resultado: Resultado
        let motivo: String
        let bytes: Int64
        let sha: String
    }

    private(set) var filas: [Fila] = []

    public init() {}

    public func agregar(entrada: String, archivo: String, tipo: String, resultado: Resultado,
                        motivo: String, bytes: Int64 = 0, sha: String = "") {
        filas.append(Fila(entrada: entrada, archivo: archivo, tipo: tipo, resultado: resultado,
                          motivo: motivo, bytes: bytes, sha: sha))
    }

    public func escribir(en url: URL) throws {
        try texto().write(to: url, atomically: true, encoding: .utf8)
    }

    func texto() -> String {
        var t = "\u{FEFF}" + tr("elemento_album;archivo;tipo;resultado;motivo;bytes;sha256") + "\n"
        for f in filas {
            t += [f.entrada, f.archivo, f.tipo, f.resultado.texto, f.motivo, String(f.bytes), f.sha]
                .map(campo).joined(separator: ";") + "\n"
        }
        return t
    }

    private func campo(_ s: String) -> String {
        guard s.contains(";") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public func resumen() -> String {
        let conteo = Dictionary(grouping: filas, by: { $0.resultado.texto }).mapValues(\.count)
        let copiados = filas.filter { $0.resultado.suma }
        let bytes = copiados.reduce(Int64(0)) { $0 + $1.bytes }
        var lineas = [tr("📊 Resumen")]
        for (resultado, n) in conteo.sorted(by: { $0.key < $1.key }) {
            lineas.append("   \(resultado): \(n)")
        }
        if copiados.first?.resultado == .seCopiaria {
            lineas.append(tr("   volumen a copiar: %@", formatoBytes(bytes)))
        } else {
            lineas.append(tr("   volumen copiado: %@", formatoBytes(bytes)))
        }
        return lineas.joined(separator: "\n")
    }
}
