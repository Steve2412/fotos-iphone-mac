import Foundation

/// Lectura mínima de la estructura de un vídeo QuickTime (.MOV) o MP4 para sacar el fabricante
/// y el modelo de la cámara leyendo solo unos KB del iPhone, sin descargar el vídeo entero.
///
/// Un vídeo es una sucesión de «átomos» (tamaño de 4 bytes + tipo de 4 letras + contenido).
/// Los datos de cámara están en el átomo `moov`, normalmente al principio o al final:
///   moov → meta → keys + ilst   (com.apple.quicktime.make / .model, como graba el iPhone)
///   moov → udta → ©mak / ©mod   (formato clásico)
public enum QuickTime {

    public struct Atomo: Equatable {
        /// Tipo de 4 caracteres (Latin-1, para que «©mak» se lea bien).
        public let tipo: String
        public let inicio: Int64
        /// Tamaño total, cabecera incluida.
        public let tamano: Int64
        /// 8 bytes, o 16 si el tamaño va en 64 bits.
        public let cabecera: Int64
    }

    /// Tamaño máximo del `moov` que se lee (los de vídeos de horas no pasan de unos MB).
    public static let moovMaximo: Int64 = 64 << 20

    /// Busca el átomo `moov` saltando de átomo en átomo y lo devuelve (sin su cabecera).
    /// `leer(desde, cantidad)` lee bytes del archivo: en el iPhone, una lectura parcial por USB.
    public static func moov(total: Int64,
                            leer: (_ desde: Int64, _ cantidad: Int64) async throws -> Data) async throws -> Data? {
        var pos: Int64 = 0
        for _ in 0..<200 {
            guard pos + 8 <= total else { return nil }
            let h = try await leer(pos, min(16, total - pos))
            guard let a = cabecera(h, inicio: pos, restante: total - pos) else { return nil }
            if a.tipo == "moov" {
                let contenido = a.tamano - a.cabecera
                guard contenido > 0, contenido <= moovMaximo else { return nil }
                return try await leer(pos + a.cabecera, contenido)
            }
            pos += a.tamano
        }
        return nil
    }

    /// Fabricante y modelo dentro del contenido de un `moov`.
    public static func camara(enMoov moov: Data) -> InfoCamara {
        var make: String?
        var model: String?
        func asignar(_ clave: String, _ valor: String) {
            let v = valor.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            guard !v.isEmpty else { return }
            switch clave {
            case "com.apple.quicktime.make", "©mak": if make == nil { make = v }
            case "com.apple.quicktime.model", "©mod": if model == nil { model = v }
            default: break
            }
        }
        for h in hijos(moov) {
            switch h.tipo {
            case "meta": leerMeta(h.datos, asignar)
            case "udta": leerUdta(h.datos, asignar)
            default: break
            }
        }
        return InfoCamara(make: make, model: model)
    }

    // MARK: Átomos

    /// Cabecera de un átomo a partir de sus primeros bytes (8, o 16 si el tamaño es de 64 bits).
    /// `restante`: bytes desde `inicio` hasta el final del archivo o del contenedor.
    public static func cabecera(_ d: Data, inicio: Int64, restante: Int64) -> Atomo? {
        guard let t32 = u32(d, 0), let tipo = tipo(d, 4) else { return nil }
        var tamano = Int64(t32)
        var cab: Int64 = 8
        if t32 == 1 {
            guard let t64 = u64(d, 8) else { return nil }
            tamano = Int64(bitPattern: t64)
            cab = 16
        } else if t32 == 0 {
            tamano = restante   // «hasta el final»
        }
        guard tamano >= cab, tamano <= restante else { return nil }
        return Atomo(tipo: tipo, inicio: inicio, tamano: tamano, cabecera: cab)
    }

    /// Átomos hijos dentro del contenido de un contenedor.
    static func hijos(_ d: Data) -> [(tipo: String, datos: Data)] {
        let d = Data(d)   // índices desde 0
        var r: [(tipo: String, datos: Data)] = []
        var pos = 0
        while pos + 8 <= d.count {
            let cab = d.subdata(in: pos..<min(d.count, pos + 16))
            guard let a = cabecera(cab, inicio: Int64(pos), restante: Int64(d.count - pos)) else { break }
            r.append((tipo: a.tipo, datos: d.subdata(in: (pos + Int(a.cabecera))..<(pos + Int(a.tamano)))))
            pos += Int(a.tamano)
        }
        return r
    }

    /// `meta` en QuickTime contiene los hijos directamente; en MP4 lleva antes 4 bytes de versión.
    static func contenidoMeta(_ d: Data) -> Data {
        let d = Data(d)
        if tipo(d, 4) == "hdlr" { return d }
        if tipo(d, 8) == "hdlr" || u32(d, 0) == 0 { return d.count > 4 ? d.subdata(in: 4..<d.count) : Data() }
        return d
    }

    static func leerMeta(_ d: Data, _ asignar: (String, String) -> Void) {
        let hs = hijos(contenidoMeta(d))
        // keys: versión (4) + número (4) + entradas [tamaño (4) + espacio de nombres (4) + clave]
        var claves: [String] = []
        if let keys = hs.first(where: { $0.tipo == "keys" })?.datos, let n = u32(keys, 4) {
            var pos = 8
            for _ in 0..<Int(min(n, 1000)) {
                guard let t = u32(keys, pos), t >= 8, pos + Int(t) <= keys.count else { break }
                claves.append(String(data: keys.subdata(in: (pos + 8)..<(pos + Int(t))), encoding: .utf8) ?? "")
                pos += Int(t)
            }
        }
        // ilst: cada hijo tiene por tipo el número de su clave (1, 2…) o un código como «©mak».
        if let ilst = hs.first(where: { $0.tipo == "ilst" })?.datos {
            var pos = 0
            while pos + 8 <= ilst.count {
                guard let t = u32(ilst, pos), t >= 8, pos + Int(t) <= ilst.count, let indice = u32(ilst, pos + 4) else { break }
                let item = ilst.subdata(in: (pos + 8)..<(pos + Int(t)))
                let clave = (indice >= 1 && Int(indice) <= claves.count) ? claves[Int(indice) - 1] : (tipo(ilst, pos + 4) ?? "")
                if let valor = valorData(item) { asignar(clave, valor) }
                pos += Int(t)
            }
        }
    }

    static func leerUdta(_ d: Data, _ asignar: (String, String) -> Void) {
        for h in hijos(d) {
            switch h.tipo {
            case "©mak", "©mod":
                if let v = valorData(h.datos) {
                    asignar(h.tipo, v)                      // estilo iTunes: átomo «data» dentro
                } else if let n = u16(h.datos, 0), 4 + Int(n) <= h.datos.count {
                    // estilo QuickTime clásico: longitud (2) + idioma (2) + texto
                    asignar(h.tipo, String(data: h.datos.subdata(in: 4..<(4 + Int(n))), encoding: .utf8) ?? "")
                }
            case "meta":
                leerMeta(h.datos, asignar)
            default:
                break
            }
        }
    }

    /// Texto dentro de un átomo `data`: tipo (4) + idioma (4) + valor.
    static func valorData(_ item: Data) -> String? {
        for h in hijos(item) where h.tipo == "data" && h.datos.count >= 8 {
            return String(data: h.datos.subdata(in: 8..<h.datos.count), encoding: .utf8)
        }
        return nil
    }

    // MARK: Bytes

    static func u16(_ d: Data, _ i: Int) -> UInt16? {
        guard i >= 0, i + 2 <= d.count else { return nil }
        let s = d.startIndex + i
        return UInt16(d[s]) << 8 | UInt16(d[s + 1])
    }

    static func u32(_ d: Data, _ i: Int) -> UInt32? {
        guard i >= 0, i + 4 <= d.count else { return nil }
        let s = d.startIndex + i
        return d[s..<(s + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    static func u64(_ d: Data, _ i: Int) -> UInt64? {
        guard i >= 0, i + 8 <= d.count else { return nil }
        let s = d.startIndex + i
        return d[s..<(s + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    static func tipo(_ d: Data, _ i: Int) -> String? {
        guard i >= 0, i + 4 <= d.count else { return nil }
        let s = d.startIndex + i
        return String(bytes: d[s..<(s + 4)], encoding: .isoLatin1)
    }
}
