import XCTest
@testable import FotosCore

final class ProgresoTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testVelocidadYRestante() {
        var m = MedidorVelocidad(ventana: 8)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(m.bytesPorSegundo)
        m.anotar(0, en: t0)
        m.anotar(5_000_000, en: t0.addingTimeInterval(0.5))
        XCTAssertNil(m.bytesPorSegundo, "menos de un segundo de muestras")
        m.anotar(20_000_000, en: t0.addingTimeInterval(2))
        XCTAssertEqual(m.bytesPorSegundo ?? 0, 10_000_000, accuracy: 1)
        XCTAssertEqual(m.restante(100_000_000) ?? 0, 10, accuracy: 0.01)
    }

    func testSoloCuentanLosUltimosSegundos() {
        var m = MedidorVelocidad(ventana: 8)
        let t0 = Date(timeIntervalSince1970: 1_000)
        // Al principio, muy rápido; después, 1 MB/s durante 20 s.
        m.anotar(0, en: t0)
        m.anotar(100_000_000, en: t0.addingTimeInterval(1))
        for s in 2...21 {
            m.anotar(100_000_000 + Int64(s - 1) * 1_000_000, en: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertEqual(m.bytesPorSegundo ?? 0, 1_000_000, accuracy: 1)
    }

    func testReiniciarTrasPausa() {
        var m = MedidorVelocidad()
        let t0 = Date(timeIntervalSince1970: 1_000)
        m.anotar(0, en: t0)
        m.anotar(10_000_000, en: t0.addingTimeInterval(2))
        m.reiniciar()
        XCTAssertNil(m.bytesPorSegundo)
        XCTAssertNil(m.restante(1))
    }

    func testFormatoDuracion() {
        XCTAssertEqual(formatoDuracion(0.2), "1 s")
        XCTAssertEqual(formatoDuracion(45), "45 s")
        XCTAssertEqual(formatoDuracion(185), "3 min")
        XCTAssertEqual(formatoDuracion(3_900), "1 h 05 min")
    }
}
