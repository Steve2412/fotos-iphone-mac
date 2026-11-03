import XCTest
@testable import FotosCore

final class PerfilesTests: XCTestCase {
    private var carpeta: URL!

    override func setUpWithError() throws {
        Idioma.elegir("es")
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("perfiles-prueba-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: carpeta)
        super.tearDown()
    }

    func testIntegrados() {
        let todos = Perfiles.todos(en: carpeta)
        XCTAssertEqual(todos.map(\.nombre), ["Respaldo completo", "Respaldo últimos días", "Viaje"])
        let completo = Perfiles.buscar("respaldo COMPLETO", en: carpeta)
        XCTAssertEqual(completo?.opciones.origenes, Set(Opciones.Origen.allCases))
        XCTAssertNil(completo?.opciones.camaras)
        let viaje = Perfiles.buscar("viaje", en: carpeta)
        XCTAssertEqual(viaje?.opciones.camaras, ["iPhone 17 Pro"])
        XCTAssertEqual(viaje?.opciones.periodo, .rangoPorIndicar)
        XCTAssertEqual(viaje?.opciones.periodo.descripcion, "en el rango de fechas que indiques")
        XCTAssertEqual(Perfiles.buscar("respaldo ultimos dias", en: carpeta)?.opciones.periodo, .ultimosDias(7))
    }

    func testGuardarYBuscar() throws {
        var op = Opciones()
        op.periodo = .ultimosDias(3)
        op.organizacion = .dia
        let url = try Perfiles.guardar(Perfil(nombre: "Viaje a Mérida / 2026", opciones: op, destino: "~/Pictures/Merida"),
                                       en: carpeta)
        XCTAssertEqual(url.lastPathComponent, "Viaje a Mérida _ 2026.json")

        let p = try XCTUnwrap(Perfiles.buscar("viaje a merida / 2026", en: carpeta))
        XCTAssertEqual(p.opciones, op)
        XCTAssertEqual(p.destino, "~/Pictures/Merida")
        XCTAssertEqual(p.urlDestino?.path, (("~/Pictures/Merida") as NSString).expandingTildeInPath)
        XCTAssertFalse(Perfiles.esIntegrado(p))
        XCTAssertEqual(Perfiles.todos(en: carpeta).count, 4)
    }

    func testUnGuardadoSustituyeAlIntegrado() throws {
        var op = Opciones()
        op.videos = false
        try Perfiles.guardar(Perfil(nombre: "Viaje", opciones: op), en: carpeta)
        let todos = Perfiles.todos(en: carpeta)
        XCTAssertEqual(todos.filter { $0.nombre == "Viaje" }.count, 1)
        XCTAssertEqual(Perfiles.buscar("viaje", en: carpeta)?.opciones.videos, false)
    }

    func testUltimaVez() {
        XCTAssertNil(Perfiles.ultima(en: carpeta))
        var op = Opciones()
        op.raw = .solo
        Perfiles.guardarUltima(Perfil(nombre: "ultima-vez", opciones: op, destino: "~/Pictures/X"), en: carpeta)
        XCTAssertEqual(Perfiles.ultima(en: carpeta)?.opciones.raw, .solo)
    }

    func testNombresIntegradosTraducidos() {
        defer { Idioma.elegir("es") }
        Idioma.elegir("en")
        XCTAssertEqual(Perfiles.integrados.map(\.nombreVisible), ["Full backup", "Recent days backup", "Trip"])
        XCTAssertEqual(Perfiles.buscar("full backup", en: carpeta)?.nombre, "Respaldo completo")
        XCTAssertEqual(Perfiles.buscar("Respaldo completo", en: carpeta)?.nombre, "Respaldo completo")
    }

    func testNombreDeArchivo() {
        XCTAssertEqual(Perfiles.nombreDeArchivo("Viaje: Japón"), "Viaje_ Japón")
        XCTAssertEqual(Perfiles.nombreDeArchivo("../../etc"), "_.._etc")
        XCTAssertEqual(Perfiles.nombreDeArchivo("///"), "___")
        XCTAssertEqual(Perfiles.nombreDeArchivo(" . "), "perfil")
    }
}

final class InformeResumenTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testConteosYMotivos() {
        let i = Informe()
        i.agregar(entrada: "1", archivo: "a", tipo: "", resultado: .seCopiaria, motivo: "", bytes: 100)
        i.agregar(entrada: "1", archivo: "b", tipo: "", resultado: .seCopiaria, motivo: "", bytes: 50)
        i.agregar(entrada: "2", archivo: "c", tipo: "", resultado: .descartado, motivo: "componente de Live Photo")
        i.agregar(entrada: "3", archivo: "d", tipo: "", resultado: .descartado, motivo: "componente de Live Photo")
        i.agregar(entrada: "4", archivo: "e", tipo: "", resultado: .descartado, motivo: "origen no elegido: captura de pantalla")
        XCTAssertEqual(i.cantidad(.seCopiaria), 2)
        XCTAssertEqual(i.cantidad(.descartado), 3)
        XCTAssertEqual(i.bytes, 150)
        let m = i.motivosDeDescarte()
        XCTAssertEqual(m.first?.motivo, "componente de Live Photo")
        XCTAssertEqual(m.first?.archivos, 2)
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(i.motivosDeDescarte(maximo: 1).count, 1)
    }

    func testEspacioLibre() {
        // Una carpeta que aún no existe: se mira su volumen.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-existe-\(UUID().uuidString)/sub")
        let libre = Disco.libre(en: url)
        XCTAssertNotNil(libre)
        XCTAssertGreaterThan(libre ?? 0, 0)
    }

    func testSePuedeEscribir() {
        let nueva = FileManager.default.temporaryDirectory.appendingPathComponent("no-existe-\(UUID().uuidString)/sub")
        XCTAssertTrue(Disco.sePuedeEscribir(en: nueva))
        // «/Desktop/…» (sin ~): la raíz del disco del sistema de macOS es de solo lectura.
        XCTAssertFalse(Disco.sePuedeEscribir(en: URL(fileURLWithPath: "/Desktop/prueba-v02")))
    }

    func testTamanoConEspacioNoSeparable() {
        XCTAssertEqual(Opciones.bytes("2\u{00A0}GB"), 2_000_000_000)
        XCTAssertEqual(Opciones.bytes(formatoBytes(2_000_000_000)), 2_000_000_000)
    }
}
