import XCTest
@testable import FotosCore

final class SimulacionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    private func archivo(_ nombre: String, _ tamano: Int64 = 100) -> Archivo {
        Archivo(nombre: nombre, tamano: tamano, fecha: Date(timeIntervalSince1970: 1_790_000_000), grupo: nil)
    }

    private func simulada(_ nombre: String, _ tipo: TipoArchivo, _ r: Resultado, _ motivo: String = "",
                          tamano: Int64 = 100) -> ArchivoSimulado {
        ArchivoSimulado(archivo: archivo(nombre, tamano), tipo: tipo, resultado: r, motivo: motivo)
    }

    func testCategoriasYContadores() {
        let s = ResultadoSimulacion()
        // Foto editada: se copian original y editada; el .AAE ya estaba.
        s.empezar("IMG_0001")
        s.agregar(etiqueta: "IMG_0001", simulada("IMG_0001.HEIC", .fotoOriginal, .seCopiaria, tamano: 3_000))
        s.agregar(etiqueta: "IMG_0001", simulada("IMG_E0001.HEIC", .fotoEditada, .seCopiaria, tamano: 2_000))
        s.agregar(etiqueta: "IMG_0001", simulada("IMG_0001.AAE", .ajustes, .yaExistia))
        // Ya copiada.
        s.empezar("IMG_0002")
        s.agregar(etiqueta: "IMG_0002", simulada("IMG_0002.HEIC", .fotoOriginal, .yaExistia))
        s.agregar(etiqueta: "IMG_0002", simulada("IMG_0002.MOV", .videoLivePhoto, .descartado, "vídeos de Live Photo no elegidos"))
        // Capturas descartadas por su origen.
        for n in ["IMG_0003", "IMG_0004"] {
            s.empezar(n)
            s.agregar(etiqueta: n, simulada("\(n).PNG", .fotoOriginal, .descartado, "origen no elegido: captura de pantalla"))
        }
        // Vídeo de otra cámara.
        s.empezar("IMG_0005")
        s.agregar(etiqueta: "IMG_0005", simulada("IMG_0005.MOV", .videoOriginal, .descartado, "tomado con «Apple iPhone 15»"))
        // Error.
        s.empezar("IMG_0006")
        s.agregar(etiqueta: "IMG_0006", simulada("IMG_0006.HEIC", .fotoOriginal, .error, "sin conexión"))
        // Ya copiado en otra carpeta: se movería (sin descargar).
        s.empezar("IMG_0007")
        s.agregar(etiqueta: "IMG_0007", simulada("IMG_0007.HEIC", .fotoOriginal, .seReubicaria, "de a a b"))

        XCTAssertEqual(s.elementos.count, 7)
        XCTAssertEqual(s.cantidad(.seCopiara), 2)
        XCTAssertEqual(s.cantidad(.yaCopiado), 1)
        XCTAssertEqual(s.cantidad(.descartado), 3)
        XCTAssertEqual(s.cantidad(.conError), 1)
        XCTAssertEqual(s.archivosACopiar, 2)
        XCTAssertEqual(s.bytesACopiar, 5_000)
        XCTAssertEqual(s.archivosAMover, 1)
        XCTAssertEqual(s.motivosDeDescarte.first?.motivo, "origen no elegido: captura de pantalla")
        XCTAssertEqual(s.motivosDeDescarte.first?.elementos, 2)
        XCTAssertEqual(s.motivosDeDescarte.count, 2)
        XCTAssertEqual(s.elementos(.conError).first?.motivo, "sin conexión")

        let video = s.elementos[4]
        XCTAssertTrue(video.esVideo)
        XCTAssertEqual(video.principal?.nombre, "IMG_0005.MOV")
        let live = s.elementos[1]
        XCTAssertTrue(live.esLivePhoto)
        XCTAssertFalse(live.esVideo)
        XCTAssertEqual(live.principal?.nombre, "IMG_0002.HEIC")
    }

    func testArchivoSinEmpezarCreaElElemento() {
        let s = ResultadoSimulacion()
        s.agregar(etiqueta: "WIOR2185", simulada("WIOR2185.MP4", .videoOriginal, .seCopiaria))
        s.agregar(etiqueta: "WIOR2185", simulada("WIOR2185.AAE", .ajustes, .descartado, "x"))
        XCTAssertEqual(s.elementos.count, 1)
        XCTAssertEqual(s.elementos[0].archivos.count, 2)
        XCTAssertEqual(s.elementos[0].categoria, .seCopiara)
    }
}
