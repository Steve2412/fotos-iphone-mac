import Foundation

public struct EntradaAlbum {
    public let linea: Int
    public let nombre: String
    public let numero: Int
    public let fecha: Date?

    public init(linea: Int, nombre: String, numero: Int, fecha: Date?) {
        self.linea = linea
        self.nombre = nombre
        self.numero = numero
        self.fecha = fecha
    }
}

/// Lee la lista que genera el Atajo: una línea por elemento, `IMG_1234|2026-10-20T14:33:12`.
/// También acepta tabulador o punto y coma como separador, y líneas sin fecha.
public enum ListaAlbum {
    public static func leer(_ url: URL) throws -> [EntradaAlbum] {
        let texto: String
        if let t = try? String(contentsOf: url, encoding: .utf8) {
            texto = t
        } else {
            var codificacion = String.Encoding.utf8
            guard let t = try? String(contentsOf: url, usedEncoding: &codificacion) else {
                throw ErrorHerramienta.lista(tr("No se pudo leer la lista: %@", url.path))
            }
            texto = t
        }

        let limpiar = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}"))
        var entradas: [EntradaAlbum] = []
        for (i, linea) in texto.components(separatedBy: .newlines).enumerated() {
            let t = linea.trimmingCharacters(in: limpiar)
            if t.isEmpty || t.hasPrefix("#") { continue }
            let campos = t.components(separatedBy: CharacterSet(charactersIn: "|\t;"))
                .map { $0.trimmingCharacters(in: limpiar) }
            guard let n = numero(de: campos[0]) else {
                print(tr("⚠️  Línea %ld ignorada (no reconozco el nombre): %@", i + 1, t))
                continue
            }
            var fecha: Date?
            if campos.count > 1, !campos[1].isEmpty {
                fecha = ListaAlbum.fecha(de: campos[1])
                if fecha == nil { print(tr("⚠️  Línea %ld: no entiendo la fecha «%@»", i + 1, campos[1])) }
            }
            entradas.append(EntradaAlbum(linea: i + 1, nombre: campos[0], numero: n, fecha: fecha))
        }
        return entradas
    }

    private static let patronNumero = try! NSRegularExpression(pattern: #"_[EOAeoa]?(\d{4,5})"#)

    public static func numero(de s: String) -> Int? {
        let rango = NSRange(s.startIndex..., in: s)
        if let m = patronNumero.firstMatch(in: s, range: rango), let r = Range(m.range(at: 1), in: s) {
            return Int(s[r])
        }
        return nil
    }

    private static let formatos = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "dd/MM/yyyy HH:mm:ss",
        "dd/MM/yyyy, HH:mm:ss",
        "dd/MM/yyyy HH:mm",
    ]

    private static let formateadores: [DateFormatter] = formatos.map { formato in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = formato
        return f
    }

    public static func fecha(de s: String) -> Date? {
        for f in formateadores {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
