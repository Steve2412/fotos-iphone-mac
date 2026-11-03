import Foundation

/// Un informe.csv de una copia, leído de nuevo para elegir qué borrar del iPhone.
///
/// El informe solo **elige los candidatos**: los elementos con algún archivo «copiado», «ya existía»
/// o «movido». Antes de borrar se sigue comprobando que el original y la edición estén de verdad
/// en el respaldo (ver Borrado), así que un informe viejo o editado a mano no puede hacer borrar
/// nada sin respaldo. Se leen informes en cualquier idioma disponible, también los de antes de la
/// v0.3 (sin las columnas de fecha y ruta).
public struct InformeLeido {
    public struct Fila: Equatable {
        public let elemento: String
        public let archivo: String
        public let resultado: String
        public let bytes: Int64
        public let fecha: Date?
        public let ruta: String
        /// El informe dice que este archivo está en el respaldo.
        public let respaldado: Bool
    }

    public let url: URL
    public let filas: [Fila]

    /// Formato de la columna de fecha (hora local, como el resto del informe).
    static let formatoFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Textos de «copiado», «ya existía» y «movido» en todos los idiomas disponibles.
    /// («copiado con aviso» no cuenta: su tamaño no coincidía.)
    static var resultadosRespaldados: Set<String> {
        let claves = ["copiado", "ya existía", "movido"]
        var r = Set(claves)
        for idioma in Idioma.disponibles {
            for c in claves { r.insert(Idioma.texto(c, enIdioma: idioma)) }
        }
        return r
    }

    public static func leer(_ url: URL) throws -> InformeLeido {
        guard var texto = try? String(contentsOf: url, encoding: .utf8) else {
            throw ErrorHerramienta.lista(tr("No se pudo leer el informe: %@", url.path))
        }
        if texto.hasPrefix("\u{FEFF}") { texto.removeFirst() }
        let lineas = texto.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let cabecera = lineas.first, campos(cabecera).count >= 7 else {
            throw ErrorHerramienta.lista(tr("«%@» no parece un informe de fotos-iphone.", url.lastPathComponent))
        }
        let respaldados = resultadosRespaldados
        var filas: [Fila] = []
        for linea in lineas.dropFirst() {
            let c = campos(linea)
            guard c.count >= 7, !c[1].isEmpty else { continue }
            let fecha = c.count > 7 && !c[7].isEmpty ? formatoFecha.date(from: c[7]) : nil
            filas.append(Fila(elemento: c[0], archivo: c[1], resultado: c[3],
                              bytes: Int64(c[5]) ?? -1, fecha: fecha,
                              ruta: c.count > 8 ? c[8] : "",
                              respaldado: respaldados.contains(c[3])))
        }
        return InformeLeido(url: url, filas: filas)
    }

    /// Elementos del catálogo que el informe da por respaldados, del más antiguo al más reciente.
    /// Un archivo del iPhone coincide con una fila si tienen el mismo nombre y tamaño y, si el
    /// informe trae la fecha, la misma fecha de captura del elemento.
    public func elementos(en catalogo: Catalogo) -> [Elemento] {
        let porClave = Dictionary(grouping: filas.filter(\.respaldado)) { "\($0.archivo)|\($0.bytes)" }
        guard !porClave.isEmpty else { return [] }
        return catalogo.todosLosElementos.filter { el in
            el.archivos.contains { a in
                (porClave["\(a.nombre)|\(a.tamano)"] ?? []).contains { f in
                    guard let ff = f.fecha, let fe = el.fecha else { return true }
                    return abs(ff.timeIntervalSince(fe)) < 1.5
                }
            }
        }
        .sorted { ($0.fecha ?? .distantPast, $0.etiqueta) < ($1.fecha ?? .distantPast, $1.etiqueta) }
    }

    /// Campos de una línea separada por «;», con comillas como las escribe Informe.
    static func campos(_ linea: String) -> [String] {
        var r: [String] = []
        var actual = ""
        var entreComillas = false
        let it = Array(linea)
        var i = 0
        while i < it.count {
            let c = it[i]
            if entreComillas {
                if c == "\"" {
                    if i + 1 < it.count && it[i + 1] == "\"" {
                        actual.append("\"")
                        i += 1
                    } else {
                        entreComillas = false
                    }
                } else {
                    actual.append(c)
                }
            } else if c == "\"" {
                entreComillas = true
            } else if c == ";" {
                r.append(actual)
                actual = ""
            } else {
                actual.append(c)
            }
            i += 1
        }
        r.append(actual)
        return r
    }
}
