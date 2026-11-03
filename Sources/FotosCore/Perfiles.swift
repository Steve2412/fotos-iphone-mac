import Foundation

/// Unas opciones con nombre («Viaje», «Respaldo completo»…) y, si se quiere, su carpeta de destino.
public struct Perfil: Codable, Equatable {
    public var nombre: String
    public var opciones: Opciones
    /// Carpeta de destino tal como se escribió (puede llevar ~).
    public var destino: String?

    public init(nombre: String, opciones: Opciones, destino: String? = nil) {
        self.nombre = nombre
        self.opciones = opciones
        self.destino = destino
    }

    /// Nombre para mostrar (los integrados se traducen).
    public var nombreVisible: String { tr(nombre) }

    public var urlDestino: URL? {
        destino.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }
}

/// Perfiles integrados y guardados. Los guardados viven en
/// ~/Library/Application Support/fotos-iphone/perfiles/<nombre>.json (nunca en el repositorio);
/// la app de la v0.3 usará los mismos.
public enum Perfiles {

    public static var carpetaPorDefecto: URL? {
        Rutas.soporte?.appendingPathComponent("perfiles", isDirectory: true)
    }

    /// Los que trae la herramienta. Un perfil guardado con el mismo nombre los sustituye.
    public static var integrados: [Perfil] {
        var completo = Opciones()
        completo.periodo = .todo
        completo.origenes = Set(Opciones.Origen.allCases)
        completo.esteIPhone = false
        completo.camaras = nil
        completo.videosLivePhoto = true
        completo.organizacion = .anioMes

        var recientes = Opciones()
        recientes.periodo = .ultimosDias(7)
        recientes.esteIPhone = false
        recientes.camaras = nil
        recientes.versiones = .final
        recientes.organizacion = .dia

        // Como la v0.1 (fotos y vídeos de la cámara de este iPhone, original + editada), para el
        // rango de fechas del viaje: el periodo se pregunta (o se da con --desde/--hasta).
        var viaje = Opciones()
        viaje.periodo = .rango(desde: nil, hasta: nil)

        return [
            Perfil(nombre: "Respaldo completo", opciones: completo),
            Perfil(nombre: "Respaldo últimos días", opciones: recientes),
            Perfil(nombre: "Viaje", opciones: viaje),
        ]
    }

    public static func esIntegrado(_ p: Perfil) -> Bool {
        integrados.contains { mismoNombre($0, p.nombre) }
    }

    /// ¿Hay un archivo guardado con este nombre? (Los integrados no lo tienen, salvo que se actualizaran.)
    public static func esGuardado(_ nombre: String, en carpeta: URL? = carpetaPorDefecto) -> Bool {
        guardados(en: carpeta).contains { mismoNombre($0, nombre) }
    }

    /// Borra un perfil guardado. Los integrados no se pueden borrar; si se habían actualizado,
    /// se borra la versión guardada y vuelve la integrada.
    public static func borrar(_ nombre: String, en carpeta: URL? = carpetaPorDefecto) throws {
        guard let carpeta, let p = guardados(en: carpeta).first(where: { mismoNombre($0, nombre) }) else {
            if integrados.contains(where: { mismoNombre($0, nombre) }) {
                throw ErrorHerramienta.argumentos(tr("«%@» es un perfil integrado: no se puede borrar.", tr(nombre)))
            }
            throw ErrorHerramienta.argumentos(tr("No existe el perfil «%@». Mira los disponibles con --perfiles.", nombre))
        }
        try FileManager.default.removeItem(at: carpeta.appendingPathComponent(nombreDeArchivo(p.nombre) + ".json"))
    }

    /// Perfiles guardados por el usuario, por orden alfabético.
    public static func guardados(en carpeta: URL? = carpetaPorDefecto) -> [Perfil] {
        guard let carpeta,
              let urls = try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)
        else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? d.decode(Perfil.self, from: Data(contentsOf: $0)) }
            .sorted { $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending }
    }

    /// Integrados (salvo los sustituidos por uno guardado del mismo nombre) y después los guardados.
    public static func todos(en carpeta: URL? = carpetaPorDefecto) -> [Perfil] {
        let propios = guardados(en: carpeta)
        let base = integrados.filter { i in !propios.contains { mismoNombre($0, i.nombre) } }
        return base + propios
    }

    /// Busca por nombre, sin distinguir mayúsculas ni tildes, en español o en el idioma en uso.
    public static func buscar(_ nombre: String, en carpeta: URL? = carpetaPorDefecto) -> Perfil? {
        todos(en: carpeta).first { mismoNombre($0, nombre) }
    }

    /// Guarda el perfil (sustituye al que tenga el mismo nombre). Devuelve dónde quedó.
    @discardableResult
    public static func guardar(_ p: Perfil, en carpeta: URL? = carpetaPorDefecto) throws -> URL {
        guard let carpeta else { throw ErrorHerramienta.copia(tr("No encuentro la carpeta de perfiles.")) }
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let url = carpeta.appendingPathComponent(nombreDeArchivo(p.nombre) + ".json")
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(p).write(to: url, options: .atomic)
        return url
    }

    // MARK: Última vez

    /// Lo elegido la última vez en el asistente: sirve de respuesta por defecto la siguiente.
    public static func ultima(en carpeta: URL? = Rutas.soporte) -> Perfil? {
        guard let url = carpeta?.appendingPathComponent("ultima-vez.json"),
              let datos = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard var p = try? d.decode(Perfil.self, from: datos) else { return nil }
        // De la v0.2: el «iPhone 17 Pro» fijo era el valor por defecto; ahora lo es «este iPhone».
        let texto = String(decoding: datos, as: UTF8.self)
        if !texto.contains("\"esteIPhone\""), p.opciones.camaras == ["iPhone 17 Pro"] {
            p.opciones.esteIPhone = true
            p.opciones.camaras = nil
        }
        return p
    }

    public static func guardarUltima(_ p: Perfil, en carpeta: URL? = Rutas.soporte) {
        guard let carpeta else { return }
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(p).write(to: carpeta.appendingPathComponent("ultima-vez.json"), options: .atomic)
    }

    // MARK: Ayudas

    static func mismoNombre(_ p: Perfil, _ nombre: String) -> Bool {
        let n = normalizar(nombre)
        return normalizar(p.nombre) == n || normalizar(p.nombreVisible) == n
    }

    /// «Viaje a Mérida / 2026» → «Viaje a Mérida _ 2026».
    static func nombreDeArchivo(_ nombre: String) -> String {
        let permitidos = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let limpio = String(nombre.unicodeScalars.map { permitidos.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return limpio.isEmpty ? "perfil" : limpio
    }
}

/// Espacio libre y permisos del disco de destino.
public enum Disco {
    /// Bytes libres en el volumen de `url` (o de su carpeta más cercana que exista).
    public static func libre(en url: URL) -> Int64? {
        guard let u = carpetaExistente(url) else { return nil }
        let v = try? u.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    /// ¿Se puede crear o escribir `url`? Se mira la carpeta más cercana que ya exista
    /// (p. ej. «/Desktop/x» no: la raíz del disco del sistema es de solo lectura).
    public static func sePuedeEscribir(en url: URL) -> Bool {
        guard let u = carpetaExistente(url) else { return false }
        var esCarpeta: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &esCarpeta), esCarpeta.boolValue else {
            return false
        }
        return FileManager.default.isWritableFile(atPath: u.path)
    }

    /// `url` o la carpeta más cercana por encima que exista.
    static func carpetaExistente(_ url: URL) -> URL? {
        var u = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: u.path) {
            let padre = u.deletingLastPathComponent()
            if padre.path == u.path { return nil }
            u = padre
        }
        return u
    }
}
