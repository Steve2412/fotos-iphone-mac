import XCTest
@testable import FotosCore

final class InformeLeidoTests: XCTestCase {
    private var carpeta: URL!

    override func setUpWithError() throws {
        Idioma.elegir("es")
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("informe-prueba-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Idioma.elegir("es")
        try? FileManager.default.removeItem(at: carpeta)
        super.tearDown()
    }

    private func fecha(_ s: String) -> Date { InformeLeido.formatoFecha.date(from: s)! }

    private func escribir(_ texto: String) throws -> URL {
        let url = carpeta.appendingPathComponent("informe.csv")
        try texto.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testCamposConComillas() {
        XCTAssertEqual(InformeLeido.campos(#"a;"b;c";"d ""e""";"#), ["a", "b;c", #"d "e""#, ""])
    }

    func testEscribirYLeerElMismoInforme() throws {
        let i = Informe()
        let f = fecha("2026-11-02 21:23:26")
        i.agregar(entrada: "IMG_8106", archivo: "IMG_8106.HEIC", tipo: "foto original", resultado: .copiado,
                  motivo: "", bytes: 3_000_000, fecha: f, ruta: "2026/2026-11/IMG_8106.HEIC")
        i.agregar(entrada: "IMG_8107", archivo: "IMG_8107.MOV", tipo: "vídeo de Live Photo", resultado: .descartado,
                  motivo: "componente; de Live Photo", bytes: 2_000_000, fecha: f)
        let url = carpeta.appendingPathComponent("informe.csv")
        try i.escribir(en: url)

        let leido = try InformeLeido.leer(url)
        XCTAssertEqual(leido.filas.count, 2)
        XCTAssertEqual(leido.filas[0].ruta, "2026/2026-11/IMG_8106.HEIC")
        XCTAssertEqual(leido.filas[0].fecha, f)
        XCTAssertTrue(leido.filas[0].respaldado)
        XCTAssertFalse(leido.filas[1].respaldado)
    }

    func testInformeEnInglesYAntiguo() throws {
        // Informe en inglés y sin las columnas de fecha y ruta (como los de antes de la v0.3).
        let url = try escribir("""
        \u{FEFF}album_item;file;type;result;reason;bytes;sha256
        IMG_0001;IMG_0001.HEIC;original photo;copied;;1000;
        IMG_0002;IMG_0002.HEIC;original photo;already existed;;2000;
        IMG_0003;IMG_0003.HEIC;original photo;skipped;taken with x;3000;
        IMG_0004;IMG_0004.HEIC;original photo;copied with warning;;4000;
        """)
        let leido = try InformeLeido.leer(url)
        XCTAssertEqual(leido.filas.filter(\.respaldado).map(\.elemento), ["IMG_0001", "IMG_0002"])
        XCTAssertNil(leido.filas[0].fecha)
    }

    func testNoEsUnInforme() throws {
        let url = try escribir("hola\nesto no es un informe\n")
        XCTAssertThrowsError(try InformeLeido.leer(url))
    }

    func testElementosDelCatalogoSegunElInforme() throws {
        // Dos IMG_0001 (el contador dio la vuelta): el informe con fecha elige el correcto.
        let viejo = fecha("2017-05-01 10:00:00")
        let nuevo = fecha("2026-11-02 21:23:26")
        let catalogo = Catalogo(archivos: [
            Archivo(nombre: "IMG_0001.HEIC", tamano: 1000, fecha: viejo, grupo: "A"),
            Archivo(nombre: "IMG_0001.HEIC", tamano: 1000, fecha: nuevo, grupo: "B"),
            Archivo(nombre: "IMG_0002.HEIC", tamano: 2000, fecha: nuevo, grupo: "C"),
        ])
        let i = Informe()
        i.agregar(entrada: "IMG_0001", archivo: "IMG_0001.HEIC", tipo: "", resultado: .yaExistia,
                  motivo: "", bytes: 1000, fecha: nuevo, ruta: "IMG_0001.HEIC")
        i.agregar(entrada: "IMG_0002", archivo: "IMG_0002.HEIC", tipo: "", resultado: .descartado,
                  motivo: "", bytes: 2000, fecha: nuevo)
        let url = carpeta.appendingPathComponent("informe.csv")
        try i.escribir(en: url)

        let elegidos = try InformeLeido.leer(url).elementos(en: catalogo)
        XCTAssertEqual(elegidos.count, 1)
        XCTAssertEqual(elegidos.first?.fecha, nuevo)

        // A través de la configuración, como hace --borrar --informe.
        var c = Configuracion()
        c.informe = url
        XCTAssertEqual(try catalogo.elementos(segun: c).count, 1)
    }

    func testResultadosEnTodosLosIdiomas() {
        let r = InformeLeido.resultadosRespaldados
        XCTAssertTrue(r.contains("copiado"))
        XCTAssertTrue(r.contains("copied"))
        XCTAssertTrue(r.contains("ya existía"))
        XCTAssertTrue(r.contains("already existed"))
        XCTAssertTrue(r.contains("moved"))
        XCTAssertFalse(r.contains("copied with warning"))
    }
}
