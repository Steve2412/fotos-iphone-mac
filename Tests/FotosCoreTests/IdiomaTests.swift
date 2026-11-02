import XCTest
@testable import FotosCore

final class IdiomaTests: XCTestCase {
    override func tearDown() {
        Idioma.elegir("es")
        super.tearDown()
    }

    func testRecursosEncontrados() {
        XCTAssertNotNil(Idioma.recursos, "No se encontró \(Idioma.nombreRecursos) junto a las pruebas")
        XCTAssertTrue(Idioma.disponibles.contains("es"))
        XCTAssertTrue(Idioma.disponibles.contains("en"))
    }

    func testEspanol() {
        XCTAssertEqual(Idioma.elegir("es"), "es")
        XCTAssertEqual(tr("foto"), "foto")
        XCTAssertEqual(tr("📅 %ld elementos %@.", 3, "en todo el iPhone"), "📅 3 elementos en todo el iPhone.")
    }

    func testIngles() {
        XCTAssertEqual(Idioma.elegir("en"), "en")
        XCTAssertEqual(tr("foto"), "photo")
        XCTAssertEqual(tr("📅 %ld elementos %@.", 3, Opciones.Periodo.todo.descripcion), "📅 3 items on the whole iPhone.")
        XCTAssertEqual(Resultado.seCopiaria.texto, "would be copied")
        XCTAssertEqual(Motivo.origenNoElegido(.captura).texto, "source not selected: screenshot")
        XCTAssertTrue(Idioma.texto("AYUDA").contains("--simulate"))
    }

    func testVarianteRegionalYDesconocido() {
        XCTAssertEqual(Idioma.elegir("en-GB"), "en")
        XCTAssertEqual(Idioma.elegir("es-VE"), "es")
        // Un idioma sin traducción no rompe nada: se usa uno de los disponibles.
        XCTAssertTrue(Idioma.disponibles.contains(Idioma.elegir("ja")))
    }

    /// Todo texto del código que pasa por tr("…") debe tener traducción en cada idioma
    /// (y con los mismos huecos %@, %ld…). Así, al añadir un idioma o un mensaje, la prueba avisa.
    func testTodasLasClavesEstanTraducidas() throws {
        let claves = try clavesDelCodigo()
        XCTAssertGreaterThan(claves.count, 100)
        let recursos = try XCTUnwrap(Idioma.recursos)
        for idioma in Idioma.disponibles where idioma != "es" {
            let url = try XCTUnwrap(recursos.url(forResource: "Localizable", withExtension: "strings",
                                                 subdirectory: nil, localization: idioma))
            let tabla = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            XCTAssertNotNil(tabla["AYUDA"], "\(idioma): falta AYUDA")
            for clave in claves {
                guard let valor = tabla[clave] else {
                    XCTFail("\(idioma): falta la traducción de «\(clave)»")
                    continue
                }
                XCTAssertEqual(huecos(clave), huecos(valor), "\(idioma): huecos distintos en «\(clave)»")
            }
        }
    }

    // MARK: Ayudas

    private func huecos(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|@|%)"#)
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
            .map { String(s[Range($0.range, in: s)!]).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression) }
            .sorted()
    }

    /// Lee los tr("…") de las fuentes del paquete.
    private func clavesDelCodigo() throws -> Set<String> {
        let fuentes = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let re = try NSRegularExpression(pattern: #"\btr\(\s*"((?:[^"\\]|\\.)*)""#)
        var claves = Set<String>()
        let enumerador = FileManager.default.enumerator(at: fuentes, includingPropertiesForKeys: nil)
        while let url = enumerador?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let texto = try String(contentsOf: url, encoding: .utf8)
            for m in re.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)) {
                let crudo = String(texto[Range(m.range(at: 1), in: texto)!])
                claves.insert(desescapar(crudo))
            }
        }
        return claves
    }

    private func desescapar(_ s: String) -> String {
        var r = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { r.append(c); continue }
            switch n {
            case "n": r.append("\n")
            case "t": r.append("\t")
            default: r.append(n)
            }
        }
        return r
    }
}
