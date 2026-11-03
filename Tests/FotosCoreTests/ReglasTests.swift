import XCTest
@testable import FotosCore

// MARK: Ayudas

private let formato: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private func fecha(_ s: String) -> Date { formato.date(from: s)! }

private func archivo(_ nombre: String, _ tamano: Int64 = 1_000,
                     _ cuando: String = "2026-10-20 10:00:00", grupo: String? = "G1",
                     px: (Int, Int) = (0, 0)) -> Archivo {
    Archivo(nombre: nombre, tamano: tamano, fecha: fecha(cuando), grupo: grupo, ancho: px.0, alto: px.1)
}

/// Live Photo editada, tal como la muestra iOS 26 por USB.
private func livePhotoEditada() -> [Archivo] {
    [
        archivo("IMG_8421.HEIC"),
        archivo("IMG_8421.MOV"),
        archivo("IMG_8421.AAE", 2, "2026-10-21 09:00:00", grupo: nil),
        archivo("IMG_A8421.DAT", 6_000, "2026-10-21 09:00:00", grupo: nil),
        archivo("IMG_E8421.HEIC", 1_000, "2026-10-21 09:00:00", grupo: nil),
        archivo("IMG_E8421.MOV", 1_000, "2026-10-21 09:00:00", grupo: nil),
    ]
}

private func unElemento(_ archivos: [Archivo]) -> Elemento {
    let c = Catalogo(archivos: archivos)
    XCTAssertEqual(c.todosLosElementos.count, 1)
    return c.todosLosElementos[0]
}

private func copiados(_ el: Elemento, _ op: Opciones) -> Set<String> {
    Set(Reglas.clasificar(el, op).filter(\.conservar).map(\.archivo.nombre))
}

private func motivo(_ nombre: String, _ el: Elemento, _ op: Opciones) -> Motivo? {
    Reglas.clasificar(el, op).first { $0.archivo.nombre == nombre }?.motivo
}

// MARK: Agrupación

final class AgrupacionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testLivePhotoEditadaEsUnSoloElemento() {
        let el = unElemento(livePhotoEditada())
        XCTAssertEqual(el.archivos.count, 6)
        XCTAssertEqual(el.imagenOriginal?.nombre, "IMG_8421.HEIC")
        XCTAssertEqual(el.fecha, fecha("2026-10-20 10:00:00"))
    }

    func testContadorQueDaLaVuelta() {
        let c = Catalogo(archivos: [
            archivo("IMG_0001.HEIC", 1_000, "2025-01-01 12:00:00", grupo: "A"),
            archivo("IMG_0001.HEIC", 2_000, "2026-03-01 12:00:00", grupo: "B"),
            archivo("IMG_E0001.HEIC", 3_000, "2026-03-05 12:00:00", grupo: nil),
        ])
        let elementos = c.porNumero[1]!.sorted { $0.fecha! < $1.fecha! }
        XCTAssertEqual(elementos.count, 2)
        XCTAssertEqual(elementos[0].archivos.count, 1)
        XCTAssertEqual(elementos[1].archivos.map(\.nombre).sorted(), ["IMG_0001.HEIC", "IMG_E0001.HEIC"])
    }

    func testArchivosRepetidosSeCuentanUnaVez() {
        let c = Catalogo(archivos: [archivo("IMG_0005.HEIC"), archivo("IMG_0005.HEIC")])
        XCTAssertEqual(c.cantidadArchivos, 1)
    }

    func testOtrasAppsSonElementosPropios() {
        let c = Catalogo(archivos: [
            archivo("THQV8599.JPG", 1, grupo: nil),
            archivo("CTFG5923.MP4", 1, grupo: nil),
            archivo("IMG_0005.HEIC", 1, grupo: "G5"),
        ])
        XCTAssertEqual(c.sinNumero.map(\.nombre), ["THQV8599.JPG", "CTFG5923.MP4"])
        XCTAssertEqual(c.otrosElementos.map(\.etiqueta), ["THQV8599", "CTFG5923"])
        XCTAssertEqual(c.todosLosElementos.count, 3)
        XCTAssertNil(c.otrosElementos[0].numero)
        XCTAssertEqual(c.otrosElementos[0].descripcion, "foto")
        XCTAssertEqual(c.otrosElementos[1].descripcion, "vídeo")
    }

    func testOtrasAppsConCompaneroSeAgrupan() {
        let c = Catalogo(archivos: [archivo("ABCD1234.JPG", 1, grupo: nil), archivo("ABCD1234.MOV", 1, grupo: nil)])
        XCTAssertEqual(c.otrosElementos.count, 1)
        XCTAssertEqual(c.otrosElementos[0].archivos.count, 2)
    }

    func testElementosConcretos() throws {
        let c = Catalogo(archivos: [
            archivo("IMG_0010.HEIC", 1, "2026-10-03 10:00:00", grupo: "x"),
            archivo("IMG_0011.HEIC", 1, "2026-10-04 10:00:00", grupo: "y"),
            archivo("THQV8599.JPG", 1, "2026-10-05 10:00:00", grupo: nil),
        ])
        var conf = Configuracion()
        XCTAssertEqual(try c.elementos(segun: conf).count, 3)
        conf.numeros = [11]
        conf.nombres = ["thqv8599"]
        XCTAssertEqual(try c.elementos(segun: conf).map(\.etiqueta), ["IMG_0011", "THQV8599"])
        conf.opciones.periodo = .rango(desde: fecha("2026-10-05 00:00:00"), hasta: nil)
        XCTAssertEqual(try c.elementos(segun: conf).map(\.etiqueta), ["THQV8599"])
    }

    func testElementosEnPeriodoOrdenados() {
        let c = Catalogo(archivos: [
            archivo("IMG_0010.HEIC", 1, "2026-10-03 10:00:00", grupo: "x"),
            archivo("IMG_0009.HEIC", 1, "2026-10-01 10:00:00", grupo: "y"),
            archivo("IMG_0011.HEIC", 1, "2026-11-01 10:00:00", grupo: "z"),
        ])
        let p = Opciones.Periodo.rango(desde: fecha("2026-10-01 00:00:00"), hasta: fecha("2026-10-31 23:59:59"))
        XCTAssertEqual(c.elementos(en: p).map(\.numero), [9, 10])
    }
}

// MARK: Reglas

final class ReglasTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testPorDefectoComoLaV01() {
        let el = unElemento(livePhotoEditada())
        let op = Opciones()
        XCTAssertEqual(copiados(el, op), ["IMG_8421.HEIC", "IMG_E8421.HEIC", "IMG_8421.AAE"])
        XCTAssertEqual(motivo("IMG_8421.MOV", el, op), .componenteLivePhoto)
        XCTAssertEqual(motivo("IMG_E8421.MOV", el, op), .componenteLivePhoto)
        XCTAssertEqual(motivo("IMG_A8421.DAT", el, op), .acompanaVideoLivePhoto)
        // Mismo orden que la v0.1: originales, editadas, .AAE, auxiliares.
        let orden = Reglas.clasificar(el, op).map(\.archivo.nombre)
        XCTAssertEqual(orden.first, "IMG_8421.HEIC")
    }

    func testSoloOriginales() {
        let el = unElemento(livePhotoEditada())
        var op = Opciones(); op.versiones = .originales
        XCTAssertEqual(copiados(el, op), ["IMG_8421.HEIC"])
        XCTAssertEqual(motivo("IMG_E8421.HEIC", el, op), .edicionNoElegida)
        XCTAssertEqual(motivo("IMG_8421.AAE", el, op), .ajustesNoElegidos)
    }

    func testVersionFinal() {
        let el = unElemento(livePhotoEditada())
        var op = Opciones(); op.versiones = .final
        XCTAssertEqual(copiados(el, op), ["IMG_E8421.HEIC"])
        XCTAssertEqual(motivo("IMG_8421.HEIC", el, op), .originalSustituido)

        let sinEditar = unElemento([archivo("IMG_0100.HEIC")])
        XCTAssertEqual(copiados(sinEditar, op), ["IMG_0100.HEIC"])
    }

    func testVersionFinalConLivePhoto() {
        let el = unElemento(livePhotoEditada())
        var op = Opciones(); op.versiones = .final; op.videosLivePhoto = true
        XCTAssertEqual(copiados(el, op), ["IMG_E8421.HEIC", "IMG_E8421.MOV"])
    }

    func testTodoIncluidoConLivePhoto() {
        let el = unElemento(livePhotoEditada())
        var op = Opciones(); op.videosLivePhoto = true
        XCTAssertEqual(copiados(el, op).count, 6)
    }

    func testSinAAE() {
        let el = unElemento(livePhotoEditada())
        var op = Opciones(); op.aae = false
        XCTAssertEqual(copiados(el, op), ["IMG_8421.HEIC", "IMG_E8421.HEIC"])
    }

    func testSinVideos() {
        let el = unElemento([archivo("IMG_0200.MOV", 5_000_000_000), archivo("IMG_0200.AAE", 2, grupo: nil)])
        var op = Opciones(); op.videos = false
        XCTAssertTrue(copiados(el, op).isEmpty)
        XCTAssertEqual(motivo("IMG_0200.MOV", el, op), .videosExcluidos)
        XCTAssertEqual(motivo("IMG_0200.AAE", el, op), .videosExcluidos)
    }

    func testVideoDemasiadoGrande() {
        let el = unElemento([archivo("IMG_0200.MOV", 5_000_000_000), archivo("IMG_0200.AAE", 2, grupo: nil)])
        var op = Opciones(); op.videoMaximo = 1_000_000_000
        XCTAssertTrue(copiados(el, op).isEmpty)
        XCTAssertEqual(motivo("IMG_0200.MOV", el, op), .videoDemasiadoGrande(limite: 1_000_000_000))
        XCTAssertEqual(motivo("IMG_0200.AAE", el, op), .sinVersionCopiada)

        op.videoMaximo = 10_000_000_000
        XCTAssertEqual(copiados(el, op), ["IMG_0200.MOV", "IMG_0200.AAE"])
    }

    func testRAW() {
        let raw = unElemento([archivo("IMG_0300.DNG")])
        let heic = unElemento([archivo("IMG_0301.HEIC")])
        var op = Opciones()

        op.raw = .excluir
        XCTAssertEqual(motivo("IMG_0300.DNG", raw, op), .rawExcluido)
        XCTAssertEqual(copiados(heic, op), ["IMG_0301.HEIC"])

        op.raw = .solo
        XCTAssertEqual(copiados(raw, op), ["IMG_0300.DNG"])
        XCTAssertEqual(motivo("IMG_0301.HEIC", heic, op), .noEsRAW)
    }

    func testRAWEditadoConVersionFinal() {
        let el = unElemento([archivo("IMG_0300.DNG"), archivo("IMG_E0300.JPG", 1, "2026-10-21 09:00:00", grupo: nil)])
        var op = Opciones(); op.versiones = .final
        XCTAssertEqual(copiados(el, op), ["IMG_E0300.JPG"])
    }

    func testTipoNoPrevisto() {
        let el = unElemento([archivo("IMG_0400.HEIC"), archivo("IMG_0400.XYZ")])
        XCTAssertEqual(motivo("IMG_0400.XYZ", el, Opciones()), .tipoNoPrevisto(ext: "XYZ"))
    }
}

// MARK: Origen y cámara

final class OrigenTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    private let iphone17 = InfoCamara(make: "Apple", model: "iPhone 17 Pro")
    private let iphone15 = InfoCamara(make: "Apple", model: "iPhone 15")
    private let sinDatos = InfoCamara()

    func testOrigenDeCadaTipo() {
        let foto = unElemento([archivo("IMG_0001.HEIC")])
        let captura = unElemento([archivo("IMG_0002.PNG")])
        let capturaJPG = unElemento([archivo("IMG_0003.JPG")])
        let videoApp = unElemento([archivo("IMG_0005.MP4", px: (720, 1280))])
        let whatsapp = unElemento([archivo("THQV8599.JPG")])
        // Casos reales de iOS 26 por USB:
        let grabacion = unElemento([archivo("WIOR2185.MP4", px: (1206, 2622))])
        let videoWhatsapp = unElemento([archivo("URMW5828.MP4", px: (576, 1024))])
        let grabacionHorizontal = unElemento([archivo("IMG_0006.MP4", px: (2622, 1206))])
        let camara4K = unElemento([archivo("IMG_0007.MOV", px: (3840, 2160))])

        XCTAssertEqual(Reglas.origen(de: foto, info: iphone17), .camara)
        XCTAssertEqual(Reglas.origen(de: captura, info: sinDatos), .captura)
        XCTAssertEqual(Reglas.origen(de: capturaJPG, info: InfoCamara(comentario: "Screenshot")), .captura)
        XCTAssertEqual(Reglas.origen(de: capturaJPG, info: sinDatos), .otrasApps)
        XCTAssertEqual(Reglas.origen(de: grabacion, info: nil), .grabacionPantalla)
        XCTAssertEqual(Reglas.origen(de: grabacionHorizontal, info: sinDatos), .grabacionPantalla)
        XCTAssertEqual(Reglas.origen(de: videoWhatsapp, info: nil), .otrasApps)
        XCTAssertEqual(Reglas.origen(de: videoApp, info: sinDatos), .otrasApps)
        XCTAssertEqual(Reglas.origen(de: camara4K, info: iphone17), .camara)
        XCTAssertFalse(Reglas.esGrabacionDePantalla(camara4K, pantallas: Resolucion.pantallasConocidas))
        XCTAssertEqual(Reglas.origen(de: whatsapp, info: nil), .otrasApps)
        // Aunque tenga datos de cámara, un nombre que no es IMG_ cuenta como otra app.
        XCTAssertEqual(Reglas.origen(de: whatsapp, info: iphone15), .otrasApps)
    }

    func testFiltroPorDefectoComoLaV01() {
        // «Este iPhone» deducido como iPhone 17 Pro: el mismo filtro que la v0.1.
        var op = Opciones()
        op.camaras = ["iPhone 17 Pro"]
        XCTAssertNil(Reglas.motivoOrigen(.camara, info: iphone17, opciones: op))
        XCTAssertNil(Reglas.motivoOrigen(.camara, info: InfoCamara(make: "Apple", model: " iphone 17 pro "), opciones: op))
        XCTAssertEqual(Reglas.motivoOrigen(.camara, info: iphone15, opciones: op),
                       .otraCamara(camara: "Apple iPhone 15", aceptadas: ["iPhone 17 Pro"]))
        XCTAssertEqual(Reglas.motivoOrigen(.captura, info: sinDatos, opciones: op), .origenNoElegido(.captura))
        XCTAssertEqual(Reglas.motivoOrigen(.otrasApps, info: nil, opciones: op), .origenNoElegido(.otrasApps))
    }

    func testOrigenesElegidos() {
        var op = Opciones()
        op.origenes = [.camara, .captura, .otrasApps]
        XCTAssertNil(Reglas.motivoOrigen(.captura, info: sinDatos, opciones: op))
        XCTAssertNil(Reglas.motivoOrigen(.otrasApps, info: nil, opciones: op))
        XCTAssertEqual(Reglas.motivoOrigen(.grabacionPantalla, info: sinDatos, opciones: op),
                       .origenNoElegido(.grabacionPantalla))

        op.camaras = nil
        XCTAssertNil(Reglas.motivoOrigen(.camara, info: InfoCamara(make: "Canon", model: "EOS R6"), opciones: op))
    }

    func testCuandoHayQueLeerMetadatos() {
        var op = Opciones()
        XCTAssertTrue(Reglas.necesitaMetadatos(op))
        op.camaras = nil
        XCTAssertTrue(Reglas.necesitaMetadatos(op))
        op.origenes = Set(Opciones.Origen.allCases)
        XCTAssertFalse(Reglas.necesitaMetadatos(op))
    }

    func testPantallasDeducidasDeLasCapturas() {
        // Un iPhone imaginario con pantalla de 1300×2800: se aprende de sus capturas.
        let c = Catalogo(archivos: [
            archivo("IMG_0010.PNG", px: (1300, 2800)),
            archivo("IMG_0011.PNG", 1, "2026-10-21 10:00:00", grupo: "x", px: (500, 500)),   // PNG cuadrado: no es pantalla
            archivo("ABCD0001.MP4", px: (1300, 2800)),
        ])
        XCTAssertTrue(c.pantallas.contains(Resolucion(1300, 2800)))
        XCTAssertFalse(c.pantallas.contains(Resolucion(500, 500)))
        XCTAssertTrue(c.pantallas.isSuperset(of: Resolucion.pantallasConocidas))
        let video = c.otrosElementos.first { $0.etiqueta == "ABCD0001" }!
        XCTAssertEqual(Reglas.origen(de: video, info: nil, pantallas: c.pantallas), .grabacionPantalla)
        XCTAssertEqual(Reglas.origen(de: video, info: nil), .otrasApps)   // sin esa captura no se sabría
    }

    func testResolucionSinOrientacion() {
        XCTAssertEqual(Resolucion(2622, 1206), Resolucion(1206, 2622))
        XCTAssertEqual(Resolucion(1206, 2622).description, "1206×2622")
        XCTAssertTrue(Resolucion(1206, 2622).pareceDePantalla)
        XCTAssertFalse(Resolucion(1080, 1920).pareceDePantalla)
    }

    func testInfoDeMetadatos() {
        let dic: [AnyHashable: Any] = ["{Exif}": ["UserComment": "Screenshot"], "PixelWidth": 1206]
        let info = DatosCamara.info(en: dic)
        XCTAssertFalse(info.tieneCamara)
        XCTAssertEqual(info.comentario, "Screenshot")
    }

    func testMakeModelDeMetadatos() {
        let dic: [AnyHashable: Any] = ["{TIFF}": ["Make": "Apple", "Model": "iPhone 17 Pro"]]
        let r = DatosCamara.makeModel(en: dic)
        XCTAssertEqual(r.make, "Apple")
        XCTAssertEqual(r.model, "iPhone 17 Pro")

        let anidado: [AnyHashable: Any] = ["{Otro}": ["x": ["Model": "iPhone 15"]]]
        XCTAssertEqual(DatosCamara.makeModel(en: anidado).model, "iPhone 15")
    }

    /// Los textos que van al informe.csv deben ser los de la v0.1.
    func testTextosDeLaV01() {
        XCTAssertEqual(Motivo.otraCamara(camara: "Apple iPhone 15", aceptadas: ["iPhone 17 Pro"]).texto,
                       "tomado con «Apple iPhone 15», no con iPhone 17 Pro")
        XCTAssertEqual(Motivo.sinOriginal.texto, "el archivo original no está en el iPhone")
        XCTAssertEqual(TipoArchivo.ajustes.texto, "ajustes de edición (.AAE)")
    }
}

// MARK: Organización y periodo

final class OrganizacionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Idioma.elegir("es")
    }

    func testRutas() {
        let f = fecha("2026-10-20 10:00:00")
        XCTAssertEqual(Reglas.rutaRelativa(nombre: "IMG_1.HEIC", fecha: f, organizacion: .plana), "IMG_1.HEIC")
        XCTAssertEqual(Reglas.rutaRelativa(nombre: "IMG_1.HEIC", fecha: f, organizacion: .anioMes), "2026/2026-10/IMG_1.HEIC")
        XCTAssertEqual(Reglas.rutaRelativa(nombre: "IMG_1.HEIC", fecha: f, organizacion: .dia), "2026/2026-10/2026-10-20/IMG_1.HEIC")
        XCTAssertEqual(Reglas.rutaRelativa(nombre: "IMG_1.HEIC", fecha: nil, organizacion: .dia), "sin-fecha/IMG_1.HEIC")
    }

    func testEdicionVaALaCarpetaDeLaCaptura() {
        // Foto del 31 de octubre editada el 2 de noviembre: todo en octubre.
        let el = unElemento([
            archivo("IMG_0500.HEIC", 1, "2026-10-31 22:00:00"),
            archivo("IMG_E0500.HEIC", 1, "2026-11-02 09:00:00", grupo: nil),
        ])
        var op = Opciones(); op.organizacion = .anioMes
        let rutas = Set(Reglas.clasificar(el, op).map(\.rutaRelativa))
        XCTAssertEqual(rutas, ["2026/2026-10/IMG_0500.HEIC", "2026/2026-10/IMG_E0500.HEIC"])
    }

    func testUltimosDias() {
        let ahora = fecha("2026-11-02 18:00:00")
        let p = Opciones.Periodo.ultimosDias(7)
        XCTAssertTrue(p.contiene(fecha("2026-10-27 00:00:00"), ahora: ahora))
        XCTAssertFalse(p.contiene(fecha("2026-10-26 23:59:59"), ahora: ahora))
        XCTAssertTrue(p.contiene(fecha("2026-11-02 17:00:00"), ahora: ahora))
        XCTAssertFalse(p.contiene(nil, ahora: ahora))
    }

    func testOpcionesSeGuardanYRecuperan() throws {
        var op = Opciones()
        op.periodo = .ultimosDias(30)
        op.versiones = .final
        op.videoMaximo = 2_000_000_000
        op.camaras = nil
        op.organizacion = .dia
        let datos = try JSONEncoder().encode(op)
        XCTAssertEqual(try JSONDecoder().decode(Opciones.self, from: datos), op)
    }
}
