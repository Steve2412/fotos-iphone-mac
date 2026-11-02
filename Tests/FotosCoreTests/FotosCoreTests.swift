import XCTest
@testable import FotosCore

final class ListaAlbumTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testNumeroDeNombres() {
        XCTAssertEqual(ListaAlbum.numero(de: "IMG_1234"), 1234)
        XCTAssertEqual(ListaAlbum.numero(de: "IMG_E8421.HEIC"), 8421)
        XCTAssertEqual(ListaAlbum.numero(de: "IMG_O0042.AAE"), 42)
        XCTAssertEqual(ListaAlbum.numero(de: "IMG_A8421.DAT"), 8421)
        XCTAssertNil(ListaAlbum.numero(de: "THQV8599.JPG"))
    }

    func testFechas() {
        XCTAssertNotNil(ListaAlbum.fecha(de: "2026-10-20T14:33:12"))
        XCTAssertNotNil(ListaAlbum.fecha(de: "2026-10-20 14:33"))
        XCTAssertNotNil(ListaAlbum.fecha(de: "20/10/2026 14:33"))
        XCTAssertNil(ListaAlbum.fecha(de: "ayer"))
    }

    func testLeerLista() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lista-prueba-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let texto = "\u{FEFF}# comentario\nIMG_1234|2026-10-20T14:33:12\n\nIMG_5678\nesto no vale\n"
        try texto.write(to: url, atomically: true, encoding: .utf8)

        let entradas = try ListaAlbum.leer(url)
        XCTAssertEqual(entradas.map(\.numero), [1234, 5678])
        XCTAssertNotNil(entradas[0].fecha)
        XCTAssertNil(entradas[1].fecha)
    }
}

final class ConfiguracionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testDia() {
        XCTAssertNotNil(Configuracion.dia("2026-01-31"))
        XCTAssertNil(Configuracion.dia("mañana"))
    }

    func testPorFechas() {
        var c = Configuracion()
        XCTAssertTrue(c.porFechas)
        c.lista = URL(fileURLWithPath: "/tmp/album.txt")
        XCTAssertFalse(c.porFechas)
        c.opciones.periodo = .rango(desde: Configuracion.dia("2026-01-01"), hasta: nil)
        XCTAssertTrue(c.porFechas)
    }

    func testOpcionesPorDefectoSonLasDeLaV01() {
        let op = Configuracion().opciones
        XCTAssertEqual(op.versiones, .originalYEditada)
        XCTAssertTrue(op.aae)
        XCTAssertFalse(op.videosLivePhoto)
        XCTAssertEqual(op.camaras, ["iPhone 17 Pro"])
        XCTAssertEqual(op.origenes, [.camara])
        XCTAssertEqual(op.organizacion, .plana)
    }
}

final class InformeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testResumenYCSV() {
        let i = Informe()
        i.agregar(entrada: "IMG_0001", archivo: "IMG_0001.HEIC", tipo: "foto original",
                  resultado: .seCopiaria, motivo: "", bytes: 1_000)
        i.agregar(entrada: "IMG_0001", archivo: "IMG_0001.MOV", tipo: "vídeo de Live Photo",
                  resultado: .descartado, motivo: "componente; de Live Photo", bytes: 500)
        let r = i.resumen()
        XCTAssertTrue(r.contains("se copiaría: 1"))
        XCTAssertTrue(r.contains("descartado: 1"))
        XCTAssertTrue(r.contains("a copiar"))
        // Un campo con «;» va entre comillas.
        XCTAssertTrue(i.texto().contains("\"componente; de Live Photo\""))
    }
}
