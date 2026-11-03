import Foundation

public enum Busqueda {
    case encontrado(Elemento)
    case noEncontrado(String)
}

/// Todos los archivos del iPhone agrupados en elementos. No depende de ImageCaptureCore:
/// el módulo del iPhone lo construye a partir del catálogo real.
public final class Catalogo {
    public let archivos: [Archivo]
    public let sinNumero: [Archivo]
    /// Elementos por número de contador (puede haber varios por número: el contador da la vuelta).
    public let porNumero: [Int: [Elemento]]
    /// Elementos de archivos que no siguen el patrón IMG_ (otras apps, descargas…).
    public let otrosElementos: [Elemento]
    /// Resoluciones de pantalla: las de las capturas (PNG) del catálogo más las conocidas.
    /// Un vídeo sin cámara con una de estas resoluciones es una grabación de pantalla.
    public let pantallas: Set<Resolucion>

    /// Cuántos archivos muestra el iPhone (principales y auxiliares).
    public var cantidadArchivos: Int { archivos.count }

    public init(archivos todos: [Archivo]) {
        var vistos = Set<String>()
        var lista: [Archivo] = []
        for a in todos {
            let clave = "\(a.nombre)|\(a.tamano)|\(a.fecha?.timeIntervalSince1970 ?? 0)"
            if vistos.insert(clave).inserted { lista.append(a) }
        }
        archivos = lista
        sinNumero = lista.filter { $0.numero == nil }
        porNumero = Catalogo.agrupar(lista)
        otrosElementos = Catalogo.agruparSinNumero(sinNumero)
        let deCapturas = lista.filter { $0.ext == "PNG" }.compactMap(\.resolucion).filter(\.pareceDePantalla)
        pantallas = Resolucion.pantallasConocidas.union(deCapturas)
    }

    public var todosLosElementos: [Elemento] { porNumero.values.flatMap { $0 } + otrosElementos }

    /// Elementos cuya fecha de captura cae en el periodo, del más antiguo al más reciente.
    public func elementos(en periodo: Opciones.Periodo, ahora: Date = Date()) -> [Elemento] {
        let (d, h) = periodo.limites(ahora: ahora)
        return todosLosElementos
            .filter { el in el.fecha.map { $0 >= d && $0 <= h } ?? false }
            .sorted { ($0.fecha!, $0.etiqueta) < ($1.fecha!, $1.etiqueta) }
    }

    /// Los archivos que no siguen el patrón IMG_ se agrupan por groupUUID o, si no lo
    /// tienen, por nombre sin extensión (THQV8599.JPG + THQV8599.MOV → un elemento).
    static func agruparSinNumero(_ archivos: [Archivo]) -> [Elemento] {
        var porClave: [String: Elemento] = [:]
        var orden: [String] = []
        for a in archivos {
            let base = (a.nombre as NSString).deletingPathExtension
            let clave = a.grupo ?? "nombre:" + base.uppercased()
            if let e = porClave[clave] {
                e.agregar(a)
            } else {
                let e = Elemento(numero: nil, etiqueta: base)
                e.agregar(a)
                porClave[clave] = e
                orden.append(clave)
            }
        }
        return orden.map { porClave[$0]! }
    }

    /// Los elementos que abarca una ejecución: los del periodo (o los de la lista del Atajo)
    /// y, si se indicaron --numero o --nombre, solo esos.
    public func elementos(segun c: Configuracion) throws -> [Elemento] {
        var r: [Elemento]
        if let informe = c.informe {
            // Los candidatos salen del informe; si además se dio un periodo, solo los de ese periodo.
            r = try InformeLeido.leer(informe).elementos(en: self)
            if c.opciones.periodo != .todo {
                r = r.filter { c.opciones.periodo.contiene($0.fecha) }
            }
        } else if c.porFechas {
            r = elementos(en: c.opciones.periodo)
        } else {
            var vistos = Set<ObjectIdentifier>()
            r = []
            for e in try ListaAlbum.leer(c.lista!) {
                if case .encontrado(let el) = buscar(e), vistos.insert(ObjectIdentifier(el)).inserted {
                    r.append(el)
                }
            }
        }
        return Catalogo.filtrar(r, numeros: c.numeros, nombres: c.nombres)
    }

    /// Solo los elementos IMG_N indicados o con esos nombres (sin filtro si ambas listas están vacías).
    public static func filtrar(_ elementos: [Elemento], numeros: [Int], nombres: [String]) -> [Elemento] {
        guard !numeros.isEmpty || !nombres.isEmpty else { return elementos }
        return elementos.filter { el in
            if let n = el.numero, numeros.contains(n) { return true }
            return nombres.contains { $0.caseInsensitiveCompare(el.etiqueta) == .orderedSame }
        }
    }

    /// Agrupa por número. Los números se repiten cada 10.000 fotos, así que dentro
    /// de un mismo número se separan los elementos por fecha.
    static func agrupar(_ archivos: [Archivo]) -> [Int: [Elemento]] {
        var resultado: [Int: [Elemento]] = [:]
        let porNumero = Dictionary(grouping: archivos.filter { $0.numero != nil }) { $0.numero! }

        for (numero, grupo) in porNumero {
            let etiqueta = String(format: "IMG_%04d", numero)
            var elementos: [Elemento] = []
            let originales = grupo.filter(\.esOriginal)
                .sorted { ($0.fecha ?? .distantPast) < ($1.fecha ?? .distantPast) }
            let derivados = grupo.filter { !$0.esOriginal }

            for a in originales {
                if let e = elementos.first(where: { mismoElemento($0, a) }) {
                    e.agregar(a)
                } else {
                    let e = Elemento(numero: numero, etiqueta: etiqueta)
                    e.agregar(a)
                    elementos.append(e)
                }
            }
            if elementos.isEmpty { elementos.append(Elemento(numero: numero, etiqueta: etiqueta)) }
            for d in derivados { elegir(para: d, entre: elementos).agregar(d) }
            resultado[numero] = elementos
        }
        return resultado
    }

    private static func mismoElemento(_ e: Elemento, _ a: Archivo) -> Bool {
        if let g = a.grupo, e.grupos.contains(g) { return true }
        guard let fa = a.fecha, let fe = e.fecha else { return true }
        return abs(fa.timeIntervalSince(fe)) <= 300
    }

    private static func elegir(para d: Archivo, entre elementos: [Elemento]) -> Elemento {
        if elementos.count == 1 { return elementos[0] }
        if let g = d.grupo, let e = elementos.first(where: { $0.grupos.contains(g) }) { return e }
        guard let fd = d.fecha else { return elementos[0] }
        // Una edición es posterior a la captura: se asocia al original más reciente anterior a ella.
        let anteriores = elementos.filter { ($0.fecha ?? .distantPast) <= fd.addingTimeInterval(300) }
        let candidatos = anteriores.isEmpty ? elementos : anteriores
        return candidatos.max { ($0.fecha ?? .distantPast) < ($1.fecha ?? .distantPast) }!
    }

    /// Busca en el iPhone el elemento que corresponde a una línea de la lista del álbum.
    public func buscar(_ entrada: EntradaAlbum) -> Busqueda {
        let etiqueta = String(format: "IMG_%04d", entrada.numero)
        guard let candidatos = porNumero[entrada.numero], !candidatos.isEmpty else {
            return .noEncontrado(tr("no está en el iPhone (¿el original solo está en iCloud?)"))
        }
        guard let f = entrada.fecha else {
            if candidatos.count == 1 { return .encontrado(candidatos[0]) }
            return .noEncontrado(tr("hay %ld %@ en el iPhone y la lista no trae fecha para distinguirlos", candidatos.count, etiqueta))
        }
        let distancia: (Elemento) -> TimeInterval = { abs(($0.fecha ?? .distantPast).timeIntervalSince(f)) }
        let mejor = candidatos.min { distancia($0) < distancia($1) }!
        // Margen amplio para absorber diferencias de zona horaria.
        if mejor.fecha != nil && distancia(mejor) > 36 * 3600 {
            return .noEncontrado(tr("en el iPhone solo hay un %@ de otra fecha (%@); el original probablemente está solo en iCloud", etiqueta, formatoFecha(mejor.fecha)))
        }
        return .encontrado(mejor)
    }
}
