import XCTest
@testable import FotosCore

// MARK: Vídeos QuickTime sintéticos

/// Átomo: tamaño (4) + tipo (4, Latin-1) + contenido.
private func atomo(_ tipo: String, _ contenido: Data) -> Data {
    var d = Data()
    let t = UInt32(8 + contenido.count)
    d.append(contentsOf: [UInt8(t >> 24), UInt8(t >> 16 & 0xFF), UInt8(t >> 8 & 0xFF), UInt8(t & 0xFF)])
    d.append(tipo.data(using: .isoLatin1)!)
    d.append(contenido)
    return d
}

private func be32(_ n: Int) -> Data {
    Data([UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)])
}

private func data(_ texto: String) -> Data {
    atomo("data", be32(1) + be32(0) + texto.data(using: .utf8)!)
}

/// moov como lo graba el iPhone: meta → hdlr + keys + ilst.
private func moovDeIPhone(make: String, model: String) -> Data {
    let hdlr = atomo("hdlr", Data(count: 8) + "mdta".data(using: .ascii)! + Data(count: 13))
    func clave(_ k: String) -> Data { be32(8 + k.utf8.count) + "mdta".data(using: .ascii)! + k.data(using: .utf8)! }
    let keys = atomo("keys", be32(0) + be32(3)
                     + clave("com.apple.quicktime.location.ISO6709")
                     + clave("com.apple.quicktime.make")
                     + clave("com.apple.quicktime.model"))
    let ilst = atomo("ilst",
                     atomo("\u{0}\u{0}\u{0}\u{1}", data("+10.4806-066.9036/"))
                     + atomo("\u{0}\u{0}\u{0}\u{2}", data(make))
                     + atomo("\u{0}\u{0}\u{0}\u{3}", data(model)))
    let mvhd = atomo("mvhd", Data(count: 100))
    return atomo("moov", mvhd + atomo("meta", hdlr + keys + ilst))
}

final class QuickTimeTests: XCTestCase {
    func testCamaraDeUnMoovDeIPhone() {
        let moov = moovDeIPhone(make: "Apple", model: "iPhone 17 Pro")
        let contenido = moov.subdata(in: 8..<moov.count)
        let info = QuickTime.camara(enMoov: contenido)
        XCTAssertEqual(info.make, "Apple")
        XCTAssertEqual(info.model, "iPhone 17 Pro")
    }

    func testCamaraEnUdtaClasico() {
        // ©mak con longitud (2) + idioma (2) + texto
        func texto(_ s: String) -> Data {
            let b = s.data(using: .utf8)!
            return Data([UInt8(b.count >> 8), UInt8(b.count & 0xFF), 0x15, 0xC7]) + b
        }
        let udta = atomo("udta", atomo("©mak", texto("Canon")) + atomo("©mod", texto("EOS R6")))
        let info = QuickTime.camara(enMoov: atomo("mvhd", Data(count: 20)) + udta)
        XCTAssertEqual(info.make, "Canon")
        XCTAssertEqual(info.model, "EOS R6")
    }

    func testSinDatosDeCamara() {
        let info = QuickTime.camara(enMoov: atomo("mvhd", Data(count: 100)))
        XCTAssertFalse(info.tieneCamara)
    }

    /// Simula el archivo en el iPhone: ftyp + mdat enorme + moov al final.
    /// Solo deben leerse las cabeceras y el moov, nunca el mdat.
    func testBuscaElMoovSaltandoElVideo() async throws {
        let ftyp = atomo("ftyp", "qt  ".data(using: .ascii)! + be32(0))
        let tamanoMdat: Int64 = 5_000_000_000   // 5 GB, tamaño en 64 bits
        var mdatCab = be32(1) + "mdat".data(using: .ascii)!
        mdatCab.append(contentsOf: (0..<8).map { UInt8((tamanoMdat >> (56 - 8 * Int64($0))) & 0xFF) })
        let moov = moovDeIPhone(make: "Apple", model: "iPhone 17 Pro")
        let inicioMoov = Int64(ftyp.count) + tamanoMdat
        let total = inicioMoov + Int64(moov.count)

        var leido: Int64 = 0
        let contenido = try await QuickTime.moov(total: total) { desde, cantidad in
            leido += cantidad
            if desde == 0 { return ftyp.prefix(Int(cantidad)) }
            if desde == Int64(ftyp.count) { return mdatCab.prefix(Int(cantidad)) }
            if desde >= inicioMoov {
                let i = Int(desde - inicioMoov)
                return moov.subdata(in: i..<min(moov.count, i + Int(cantidad)))
            }
            XCTFail("leyó dentro del vídeo en \(desde)")
            return Data(count: Int(cantidad))
        }
        let info = QuickTime.camara(enMoov: try XCTUnwrap(contenido))
        XCTAssertEqual(info.model, "iPhone 17 Pro")
        XCTAssertLessThan(leido, 10_000, "debe leer unos pocos KB, no el vídeo")
    }

    func testArchivoQueNoEsQuickTime() async throws {
        let basura = Data((0..<64).map { UInt8($0 &* 37 & 0xFF) })
        let r = try await QuickTime.moov(total: Int64(basura.count)) { desde, cantidad in
            basura.subdata(in: Int(desde)..<Int(min(Int64(basura.count), desde + cantidad)))
        }
        XCTAssertNil(r)
    }
}

// MARK: Opciones escritas en Terminal

final class OpcionesTextoTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testValoresEnLosDosIdiomas() {
        XCTAssertEqual(Opciones.Versiones(texto: "originales"), .originales)
        XCTAssertEqual(Opciones.Versiones(texto: "Originals"), .originales)
        XCTAssertEqual(Opciones.Versiones(texto: "final"), .final)
        XCTAssertEqual(Opciones.Versiones(texto: "ambas"), .originalYEditada)
        XCTAssertEqual(Opciones.Versiones(texto: "both"), .originalYEditada)
        XCTAssertNil(Opciones.Versiones(texto: "algunas"))

        XCTAssertEqual(Opciones.ModoRAW(texto: "solo"), .solo)
        XCTAssertEqual(Opciones.ModoRAW(texto: "exclude"), .excluir)
        XCTAssertEqual(Opciones.Organizacion(texto: "mes"), .anioMes)
        XCTAssertEqual(Opciones.Organizacion(texto: "Día"), .dia)
        XCTAssertEqual(Opciones.Organizacion(texto: "flat"), .plana)
    }

    func testOrigenes() {
        XCTAssertEqual(Opciones.Origen.conjunto("camara,capturas"), [.camara, .captura])
        XCTAssertEqual(Opciones.Origen.conjunto("cámara, grabaciones"), [.camara, .grabacionPantalla])
        XCTAssertEqual(Opciones.Origen.conjunto("screenshots,apps"), [.captura, .otrasApps])
        XCTAssertEqual(Opciones.Origen.conjunto("todo"), Set(Opciones.Origen.allCases))
        XCTAssertNil(Opciones.Origen.conjunto("camara,fotos"))
    }

    func testTamanos() {
        XCTAssertEqual(Opciones.bytes("2GB"), 2_000_000_000)
        XCTAssertEqual(Opciones.bytes("1.5 G"), 1_500_000_000)
        XCTAssertEqual(Opciones.bytes("1,5gb"), 1_500_000_000)
        XCTAssertEqual(Opciones.bytes("500MB"), 500_000_000)
        XCTAssertEqual(Opciones.bytes("800"), 800_000_000)
        XCTAssertNil(Opciones.bytes("mucho"))
        XCTAssertNil(Opciones.bytes("-2GB"))
    }

    func testResumen() {
        var op = Opciones()
        op.videoMaximo = 2_000_000_000
        let r = op.resumen.joined(separator: "\n")
        XCTAssertTrue(r.contains("Cámaras: iPhone 17 Pro"))
        XCTAssertTrue(r.contains("Versiones: original + editada"))
        XCTAssertTrue(r.contains("Vídeos: sí, hasta"))
        op.origenes = [.captura]
        XCTAssertFalse(op.resumen.joined().contains("Cámaras"))
    }
}

// MARK: Manifiesto y caché

final class ManifiestoTests: XCTestCase {
    private func carpetaTemporal() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-prueba-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testGuardarYLeer() throws {
        let destino = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: destino) }
        let a = Archivo(nombre: "IMG_0001.HEIC", tamano: 1234, fecha: Date(timeIntervalSince1970: 1_790_000_000), grupo: nil)
        let otro = Archivo(nombre: "IMG_0001.HEIC", tamano: 999, fecha: Date(timeIntervalSince1970: 1_500_000_000), grupo: nil)

        var m = Manifiesto()
        m.registrar(a, ruta: "2026/2026-09/IMG_0001.HEIC", elemento: "IMG_0001", sha256: "")
        m.registrar(otro, ruta: "2017/2017-07/IMG_0001 (2).HEIC", elemento: "IMG_0001")
        try m.escribir(en: destino)

        let leido = Manifiesto.leer(en: destino)
        XCTAssertEqual(leido, m)
        XCTAssertEqual(leido.ruta(de: a), "2026/2026-09/IMG_0001.HEIC")
        XCTAssertEqual(leido.ruta(de: otro), "2017/2017-07/IMG_0001 (2).HEIC")
        XCTAssertNil(leido.entradas[a.identidad]?.sha256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destino.appendingPathComponent(".fotos-iphone/manifiesto.json").path))
    }

    func testManifiestoInexistenteEstaVacio() throws {
        let destino = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: destino) }
        XCTAssertTrue(Manifiesto.leer(en: destino).entradas.isEmpty)
    }

    func testCache() throws {
        let carpeta = try carpetaTemporal()
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let url = carpeta.appendingPathComponent("cache.json")
        let a = Archivo(nombre: "IMG_0002.MOV", tamano: 50, fecha: Date(timeIntervalSince1970: 1_790_000_000), grupo: nil)

        let c = CacheCamaras(url: url)
        XCTAssertNil(c[a])
        c[a] = InfoCamara(make: "Apple", model: "iPhone 17 Pro")
        c.guardar()

        let otra = CacheCamaras(url: url)
        XCTAssertEqual(otra[a]?.model, "iPhone 17 Pro")
        XCTAssertEqual(otra.cantidad, 1)
    }
}
