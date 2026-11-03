import Foundation
import AppKit
import Observation
import ImageCaptureCore
import FotosCore
import FotosIPhoneKit

/// Estado de la app. Recibe los eventos de la biblioteca y los convierte en estado
/// observable para las vistas. Todo ocurre en el hilo principal.
@MainActor
@Observable
final class ModeloApp {

    enum Fase: Equatable {
        case buscando
        /// El iPhone rechaza la sesión (bloqueado o sin confiar todavía en el Mac).
        case esperando(String)
        case leyendoCatalogo(Int)
        case listo
        case desconectado
        /// El usuario detuvo el intento de conexión.
        case detenido
        case error(String)
    }

    var fase: Fase = .buscando
    var nombreIPhone: String?
    var bloqueado = false
    var catalogo: Catalogo?
    /// Registro de mensajes (los mismos que muestra la Terminal), para diagnosticar.
    var mensajes: [String] = []
    /// El catálogo no avanza: seguramente falta abrir Captura de Imagen.
    var sugerirCapturaDeImagen = false {
        didSet { if sugerirCapturaDeImagen && !oldValue { alertaCapturaDeImagen = true } }
    }
    /// Aviso emergente (una vez por conexión) de que no se detectan las fotos.
    var alertaCapturaDeImagen = false
    /// Al abrir la app, Captura de Imagen no estaba abierta.
    var pedirCapturaAlInicio = false

    /// ¿Está abierta Captura de Imagen? (Sin ella, macOS no entrega el catálogo del iPhone.)
    static var capturaDeImagenAbierta: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Image_Capture").isEmpty
    }

    // MARK: Opciones (se guardan como «última vez», igual que en el asistente de Terminal)

    var opciones = Opciones() { didSet { guardarUltimaVez() } }
    var destinoTexto = "~/Pictures/iPhone" { didSet { guardarUltimaVez() } }
    var perfiles: [Perfil] = Perfiles.todos()
    /// Nombre del perfil aplicado («» si se configuró a mano).
    var perfilElegido = ""
    /// El perfil tal como se aplicó, para saber si se ha cambiado algo desde entonces.
    var perfilAplicado: Perfil?
    /// Modelo de este iPhone, deducido de sus fotos recientes al conectar.
    var modeloEsteIPhone: String?
    var deduciendoModelo = false
    var camarasDetectadas: [ConteoCamara] = []

    // MARK: Simulación

    enum EstadoSimulacion: Equatable {
        case nada, simulando, lista, cancelada
        case error(String)
    }

    /// Lo que muestra la vista previa, calculado una vez al terminar la simulación.
    struct VistaPrevia {
        let resultado: ResultadoSimulacion
        let porCategoria: [ElementoSimulado.Categoria: [ElementoSimulado]]
        let motivos: [(motivo: String, elementos: Int)]
        let archivosACopiar: Int
        let bytesACopiar: Int64
        let archivosAMover: Int

        init(_ r: ResultadoSimulacion) {
            resultado = r
            porCategoria = Dictionary(grouping: r.elementos, by: \.categoria)
            motivos = r.motivosDeDescarte
            archivosACopiar = r.archivosACopiar
            bytesACopiar = r.bytesACopiar
            archivosAMover = r.archivosAMover
        }

        func elementos(_ c: ElementoSimulado.Categoria) -> [ElementoSimulado] { porCategoria[c] ?? [] }
    }

    var estadoSimulacion: EstadoSimulacion = .nada
    var simHechos = 0
    var simTotal = 0
    var vistaPrevia: VistaPrevia?
    /// Cambia con cada simulación terminada (para que la vista elija qué grupo enseñar).
    var numeroSimulacion = 0
    var informeSimulacion: URL?
    private var opcionesSimuladas: Opciones?
    private var destinoSimulado: String?
    @ObservationIgnored private var simulacionEnCurso: ResultadoSimulacion?
    @ObservationIgnored private var controlSimulacion: ControlCopia?
    @ObservationIgnored let miniaturas = Miniaturas()

    // MARK: Copia

    enum EstadoCopia: Equatable {
        case nada, copiando, terminada, cancelada
        case error(String)
    }

    struct ProgresoCopia {
        var elementosHechos = 0
        var elementosTotal = 0
        /// Bytes de los archivos ya terminados.
        var bytesHechos: Int64 = 0
        /// Lo que se espera copiar (de la simulación).
        var bytesTotal: Int64 = 0
        var archivoActual: String?
        var fraccionActual = 0.0
        var tamanoActual: Int64 = 0
        var velocidad: Double?
        var restante: TimeInterval?
        var copiados = 0
        var yaExistian = 0
        var movidos = 0
        var descartados = 0
        var errores: [String] = []
        var conAviso = 0

        /// Bytes copiados contando lo que va del archivo en curso.
        var bytesActuales: Int64 { bytesHechos + Int64(fraccionActual * Double(tamanoActual)) }

        var fraccion: Double {
            if bytesTotal > 0 { return min(Double(bytesActuales) / Double(bytesTotal), 1) }
            guard elementosTotal > 0 else { return 0 }
            return Double(elementosHechos) / Double(elementosTotal)
        }
    }

    var estadoCopia: EstadoCopia = .nada
    var progreso = ProgresoCopia()
    var pausada = false
    /// Se pidió cancelar: se detiene al terminar el archivo en curso.
    var cancelando = false
    var informeCopia: URL?
    var destinoCopia: URL?
    @ObservationIgnored private var controlCopia: ControlCopia?
    @ObservationIgnored private var medidor = MedidorVelocidad()
    @ObservationIgnored private var actividad: NSObjectProtocol?
    /// Los eventos que llegan son de la copia (y no de una simulación).
    @ObservationIgnored private var enCopia = false

    // MARK: Borrado

    /// Qué se ve a la derecha: copiar al Mac o borrar del iPhone.
    enum Seccion: Hashable { case copiar, borrar }
    var seccion: Seccion = .copiar

    /// De dónde salen los candidatos a borrar.
    enum OrigenBorrado: Hashable { case carpeta, informe }
    var origenBorrado: OrigenBorrado = .carpeta
    /// informe.csv de una copia (su carpeta es el respaldo).
    var informeParaBorrar: URL?

    enum EstadoBorrado: Equatable {
        case nada, revisando, revisado, borrando, terminado
        case error(String)
    }
    var estadoBorrado: EstadoBorrado = .nada
    var planBorrado: PlanBorrado?
    var borradoHechos = 0
    var borradoTotal = 0
    var borradoActual: String?
    /// Elementos que siguen en el iPhone tras intentar borrarlos.
    var borradoFallos: [String] = []
    var resultadoBorrado: ResultadoBorrado?
    var borradoDetenido = false
    /// Con qué se hizo el plan (si cambia, hay que revisar otra vez).
    private var firmaPlan: String?
    @ObservationIgnored private var controlBorrado: ControlCopia?
    @ObservationIgnored private var borradoEnCurso: Borrado?
    var detectandoCamaras = false

    enum TipoPeriodo: Int, CaseIterable, Identifiable {
        case todo, ultimosDias, mesAnterior, rango
        var id: Int { rawValue }
    }

    /// De qué cámaras: este iPhone (por defecto), cualquiera o las que se elijan.
    enum TipoCamara: Int, CaseIterable, Identifiable {
        case esteIPhone, cualquiera, elegir
        var id: Int { rawValue }
    }

    var tipoCamara: TipoCamara {
        get { opciones.esteIPhone ? .esteIPhone : (opciones.camaras == nil ? .cualquiera : .elegir) }
        set {
            switch newValue {
            case .esteIPhone:
                opciones.esteIPhone = true
                opciones.camaras = nil
            case .cualquiera:
                opciones.esteIPhone = false
                opciones.camaras = nil
            case .elegir:
                opciones.esteIPhone = false
                if opciones.camaras == nil {
                    opciones.camaras = [modeloEsteIPhone ?? modelosDisponibles.first].compactMap { $0 }
                }
            }
        }
    }
    /// Valores del periodo que se editan por separado y se combinan en `opciones.periodo`.
    var dias = 7 { didSet { if tipoPeriodo == .ultimosDias { opciones.periodo = .ultimosDias(max(dias, 1)) } } }
    var desde = Calendar.current.startOfDay(for: Date()) { didSet { if tipoPeriodo == .rango { opciones.periodo = rango } } }
    var hasta = Date() { didSet { if tipoPeriodo == .rango { opciones.periodo = rango } } }

    var tipoPeriodo: TipoPeriodo {
        get {
            switch opciones.periodo {
            case .todo: return .todo
            case .ultimosDias: return .ultimosDias
            case .mesAnterior: return .mesAnterior
            case .rango: return .rango
            }
        }
        set {
            switch newValue {
            case .todo: opciones.periodo = .todo
            case .ultimosDias: opciones.periodo = .ultimosDias(max(dias, 1))
            case .mesAnterior: opciones.periodo = .mesAnterior
            case .rango: opciones.periodo = rango
            }
        }
    }

    /// Del inicio del día «desde» al final del día «hasta».
    private var rango: Opciones.Periodo {
        let c = Calendar.current
        let inicio = c.startOfDay(for: desde)
        let fin = c.date(byAdding: DateComponents(day: 1, second: -1), to: c.startOfDay(for: hasta)) ?? hasta
        return .rango(desde: inicio, hasta: fin)
    }

    var destinoURL: URL {
        URL(fileURLWithPath: (destinoTexto as NSString).expandingTildeInPath).standardizedFileURL
    }

    var destinoValido: Bool { Disco.sePuedeEscribir(en: destinoURL) }

    init() {
        if let u = Perfiles.ultima() {
            opciones = u.opciones
            if let d = u.destino { destinoTexto = d }
        }
        descomponerPeriodo()
    }

    @ObservationIgnored private var conexion: ConexionIPhone?
    @ObservationIgnored private(set) var camara: ICCameraDevice?

    @ObservationIgnored private var iniciada = false

    /// La primera conexión, al abrir la ventana.
    func iniciar() async {
        guard !iniciada else { return }
        iniciada = true
        if Self.capturaDeImagenAbierta {
            await conectar()
        } else {
            // Primero se explica y se abre Captura de Imagen (lo hace el botón del aviso).
            fase = .detenido
            pedirCapturaAlInicio = true
        }
    }

    /// Abre Captura de Imagen en segundo plano y deja esta app delante.
    func abrirCapturaDeImagen() async {
        let url = URL(fileURLWithPath: "/System/Applications/Image Capture.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Botón del aviso inicial.
    func abrirCapturaDeImagenYConectar() async {
        pedirCapturaAlInicio = false
        await abrirCapturaDeImagen()
        await conectar()
    }

    /// Fases en las que se está intentando conectar (y se puede detener).
    var conectando: Bool {
        switch fase {
        case .buscando, .esperando, .leyendoCatalogo: return true
        default: return false
        }
    }

    /// Detiene el intento de conexión; luego se puede volver a intentar con Reconectar.
    func detenerConexion() {
        guard conectando, let c = conexion else { return }
        conexion = nil
        c.observador = { _ in }
        c.cerrar()
        fase = .detenido
        sugerirCapturaDeImagen = false
        registrar(tr("⏹  Conexión detenida. Pulsa Reconectar para volver a intentarlo."))
    }

    /// Conecta (o vuelve a conectar) con el iPhone y lee su catálogo.
    func conectar() async {
        if let anterior = conexion {
            anterior.observador = { _ in }
            anterior.cerrar()
        }
        sugerirCapturaDeImagen = false
        alertaCapturaDeImagen = false
        let c = ConexionIPhone()
        conexion = c
        fase = .buscando
        olvidarSimulacion()
        catalogo = nil
        camara = nil
        nombreIPhone = nil
        bloqueado = false
        // Los eventos llegan siempre en el hilo principal.
        c.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        do {
            let cam = try await c.conectar(segundos: 180)
            camara = cam
            let cat = Catalogo(camara: cam)
            catalogo = cat
            fase = .listo
            registrar(tr("📚 El iPhone muestra %ld archivos.\n", cat.cantidadArchivos))
            // Sin archivos: casi seguro falta Captura de Imagen abierta.
            if cat.cantidadArchivos == 0 {
                sugerirCapturaDeImagen = true
            } else {
                sugerirCapturaDeImagen = false
                alertaCapturaDeImagen = false
            }
            await deducirModelo(cat)
        } catch {
            // Si mientras tanto se pidió otra conexión, este error ya no interesa.
            guard conexion === c else { return }
            fase = .error(error.localizedDescription)
            registrar("❌ " + error.localizedDescription)
        }
    }

    // MARK: Simular

    var simulando: Bool { estadoSimulacion == .simulando }

    /// Por qué no se puede simular ahora (nil si se puede).
    var motivoNoSimular: String? {
        if catalogo == nil || fase != .listo { return tr("Conecta el iPhone para simular.") }
        if opciones.origenes.isEmpty { return tr("Elige al menos un origen.") }
        if tipoCamara == .elegir && (opciones.camaras ?? []).isEmpty { return tr("Elige al menos una cámara.") }
        return nil
    }

    var puedeSimular: Bool { motivoNoSimular == nil && !ocupado }

    var copiando: Bool { estadoCopia == .copiando }
    /// Simulando o copiando: no se cambian opciones ni se reconecta.
    var ocupado: Bool { simulando || copiando || borrando || estadoBorrado == .revisando }

    var borrando: Bool { estadoBorrado == .borrando }

    /// Las opciones o el destino cambiaron después de simular.
    var simulacionDesactualizada: Bool {
        guard vistaPrevia != nil, let o = opcionesSimuladas else { return false }
        return o.sinDeducciones != opciones.sinDeducciones || destinoSimulado != destinoTexto
    }

    /// Simula con las opciones del panel: no copia ni borra nada. Si la carpeta de destino ya existe,
    /// también dice qué está ya copiado en ella.
    func simular() async {
        guard let catalogo, puedeSimular else { return }
        var c = Configuracion()
        c.modo = .transferir
        c.opciones = opciones
        c.simular = true
        c.detalle = false
        c.mostrarOpciones = false
        c.confirmar = false
        if FileManager.default.fileExists(atPath: destinoURL.path) { c.destino = destinoURL }

        let t = Transferencia(config: c, catalogo: catalogo)
        let control = ControlCopia()
        t.control = control
        t.rutaInformeSimulacion = (Rutas.soporte ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("informe-simulacion.csv")
        t.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        controlSimulacion = control
        simulacionEnCurso = ResultadoSimulacion()
        simHechos = 0
        simTotal = 0
        estadoSimulacion = .simulando
        let op = opciones, destino = destinoTexto
        defer {
            simulacionEnCurso = nil
            controlSimulacion = nil
        }
        do {
            try await t.ejecutar()
            // Si mientras tanto se reconectó, esta simulación ya no vale.
            guard self.catalogo === catalogo, let r = simulacionEnCurso else {
                estadoSimulacion = .nada
                return
            }
            vistaPrevia = VistaPrevia(r)
            opcionesSimuladas = op
            destinoSimulado = destino
            numeroSimulacion += 1
            estadoSimulacion = control.cancelado ? .cancelada : .lista
        } catch {
            guard self.catalogo === catalogo else {
                estadoSimulacion = .nada
                return
            }
            estadoSimulacion = .error(error.localizedDescription)
            registrar("❌ " + error.localizedDescription)
        }
    }

    // MARK: Copiar

    /// Por qué no se puede copiar ahora (nil si se puede). Siempre hace falta una simulación
    /// completa y al día: lo que se copia es lo que se ha visto en la vista previa.
    var motivoNoCopiar: String? {
        if catalogo == nil || fase != .listo { return tr("Conecta el iPhone para copiar.") }
        guard let v = vistaPrevia else { return tr("Simula primero para ver qué se copiaría.") }
        if estadoSimulacion != .lista { return tr("La última simulación no terminó: vuelve a simular antes de copiar.") }
        if simulacionDesactualizada { return tr("Has cambiado las opciones o el destino: vuelve a simular antes de copiar.") }
        if !destinoValido { return tr("No se puede escribir en esa carpeta.") }
        if v.archivosACopiar + v.archivosAMover == 0 { return tr("Nada que copiar con estas opciones.") }
        return nil
    }

    var puedeCopiar: Bool { motivoNoCopiar == nil && !ocupado }

    /// Espacio libre en el disco de destino.
    var espacioLibre: Int64? { Disco.libre(en: destinoURL) }

    var faltaEspacio: Bool {
        guard let libre = espacioLibre, let v = vistaPrevia else { return false }
        return libre < v.bytesACopiar
    }

    /// Copia de verdad lo que se vio en la simulación. Lo ya copiado se salta; no se borra nada del iPhone.
    func copiar() async {
        guard let catalogo, puedeCopiar, let v = vistaPrevia, let op = opcionesSimuladas else { return }
        var c = Configuracion()
        c.modo = .transferir
        c.opciones = op
        c.simular = false
        c.detalle = false
        c.mostrarOpciones = false
        c.confirmar = false
        c.destino = destinoURL

        let t = Transferencia(config: c, catalogo: catalogo)
        let control = ControlCopia()
        t.control = control
        t.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        controlCopia = control
        enCopia = true
        medidor = MedidorVelocidad()
        progreso = ProgresoCopia()
        progreso.bytesTotal = v.bytesACopiar
        pausada = false
        cancelando = false
        informeCopia = nil
        destinoCopia = destinoURL
        estadoCopia = .copiando
        // Que el Mac no se duerma a mitad de copia.
        actividad = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated], reason: tr("Copiando fotos del iPhone"))
        registrar(tr("📥 Copiando a %@", destinoURL.path))
        defer {
            if let a = actividad { ProcessInfo.processInfo.endActivity(a) }
            actividad = nil
            controlCopia = nil
            enCopia = false
            pausada = false
            cancelando = false
            progreso.archivoActual = nil
            // Lo que había en la vista previa ya no refleja el destino.
            vistaPrevia = nil
            opcionesSimuladas = nil
            if estadoSimulacion != .simulando { estadoSimulacion = .nada }
        }
        do {
            try await t.ejecutar()
            if fase == .desconectado {
                estadoCopia = .error(tr("El iPhone se desconectó. Vuelve a conectarlo y copia otra vez: lo ya copiado se salta."))
            } else {
                estadoCopia = control.cancelado ? .cancelada : .terminada
            }
        } catch {
            estadoCopia = .error(error.localizedDescription)
            registrar("❌ " + error.localizedDescription)
        }
    }

    /// La pausa y la cancelación se aplican al terminar el archivo en curso.
    func pausar(_ p: Bool) {
        controlCopia?.pausado = p
        pausada = p
        medidor.reiniciar()
        progreso.velocidad = nil
        progreso.restante = nil
    }

    func cancelarCopia() {
        cancelando = true
        pausada = false
        controlCopia?.cancelar()
    }

    /// Vuelve a la pantalla de opciones tras una copia.
    func cerrarCopia() {
        guard !copiando else { return }
        estadoCopia = .nada
    }

    private func anotarVelocidad() {
        guard !pausada else { return }
        medidor.anotar(progreso.bytesActuales)
        progreso.velocidad = medidor.bytesPorSegundo
        progreso.restante = medidor.restante(progreso.bytesTotal - progreso.bytesActuales)
    }

    // MARK: Borrar

    /// La carpeta del respaldo que se comprueba antes de borrar.
    var carpetaRespaldo: URL? {
        switch origenBorrado {
        case .carpeta: return destinoURL
        case .informe: return informeParaBorrar?.deletingLastPathComponent().standardizedFileURL
        }
    }

    private var firmaActual: String {
        [origenBorrado == .carpeta ? "carpeta" : "informe",
         carpetaRespaldo?.path ?? "",
         informeParaBorrar?.path ?? "",
         origenBorrado == .carpeta ? opciones.periodo.descripcion : "",
         opciones.organizacion.texto].joined(separator: "|")
    }

    var planDesactualizado: Bool { planBorrado != nil && firmaPlan != firmaActual }

    var motivoNoRevisar: String? {
        if catalogo == nil || camara == nil || fase != .listo { return tr("Conecta el iPhone.") }
        switch origenBorrado {
        case .carpeta:
            if !FileManager.default.fileExists(atPath: destinoURL.path) {
                return tr("No existe la carpeta del respaldo: %@", destinoURL.path)
            }
        case .informe:
            if informeParaBorrar == nil { return tr("Elige el informe.csv de una copia.") }
        }
        return nil
    }

    var motivoNoBorrar: String? {
        if let m = motivoNoRevisar { return m }
        guard let plan = planBorrado, estadoBorrado == .revisado else { return tr("Revisa primero qué se borraría.") }
        if planDesactualizado { return tr("Has cambiado la carpeta, el informe o el periodo: revisa otra vez.") }
        if plan.aBorrar.isEmpty { return tr("Nada que borrar.") }
        return nil
    }

    private func configuracionBorrado() -> Configuracion {
        var c = Configuracion()
        c.modo = .transferir
        c.borrar = true
        c.simular = true
        c.opciones = opciones
        c.destino = carpetaRespaldo
        if origenBorrado == .informe {
            c.informe = informeParaBorrar
            // Todo el informe (el periodo del panel es para copiar).
            c.opciones.periodo = .todo
        }
        return c
    }

    /// Calcula qué se borraría, sin tocar nada.
    func revisarBorrado() async {
        guard let catalogo, let camara, motivoNoRevisar == nil, !ocupado else { return }
        estadoBorrado = .revisando
        planBorrado = nil
        resultadoBorrado = nil
        // Deja que la interfaz muestre «Revisando…» antes de leer el respaldo.
        await Task.yield()
        let b = Borrado(config: configuracionBorrado(), catalogo: catalogo, camara: camara)
        b.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        do {
            let plan = try b.planificar()
            b.mostrar(plan)
            planBorrado = plan
            firmaPlan = firmaActual
            estadoBorrado = .revisado
        } catch {
            estadoBorrado = .error(error.localizedDescription)
            registrar("❌ " + error.localizedDescription)
        }
    }

    /// Borra del iPhone lo del plan revisado. La vista pide antes escribir la clave.
    func borrar() async {
        guard let catalogo, let camara, motivoNoBorrar == nil, let plan = planBorrado, !ocupado else { return }
        let b = Borrado(config: configuracionBorrado(), catalogo: catalogo, camara: camara)
        let control = ControlCopia()
        b.control = control
        b.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        controlBorrado = control
        borradoEnCurso = b
        borradoHechos = 0
        borradoTotal = plan.aBorrar.count
        borradoActual = nil
        borradoFallos = []
        borradoDetenido = false
        estadoBorrado = .borrando
        actividad = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated], reason: tr("Borrando fotos del iPhone"))
        registrar(tr("🗑  Borrando del iPhone %ld elementos (respaldo en %@)", plan.aBorrar.count, b.carpetaRespaldo.path))
        let r = await b.ejecutar(plan)
        if let a = actividad { ProcessInfo.processInfo.endActivity(a) }
        actividad = nil
        resultadoBorrado = r
        borradoDetenido = control.cancelado
        controlBorrado = nil
        borradoEnCurso = nil
        planBorrado = nil
        firmaPlan = nil
        estadoBorrado = .terminado
        registrar(tr("\n📊 Archivos borrados: %ld · no borrados: %ld", r.borrados, r.fallidos))
        // Lo simulado antes ya no refleja el iPhone.
        vistaPrevia = nil
        opcionesSimuladas = nil
        if estadoSimulacion != .simulando { estadoSimulacion = .nada }
    }

    /// Se detiene al terminar el elemento en curso.
    func detenerBorrado() {
        controlBorrado?.cancelar()
    }

    /// Tras borrar: vuelve a leer el iPhone (su catálogo cambió).
    func cerrarBorradoYReconectar() async {
        estadoBorrado = .nada
        resultadoBorrado = nil
        await conectar()
    }

    func cancelarSimulacion() {
        controlSimulacion?.cancelar()
    }

    /// Al desconectar o reconectar, la vista previa ya no sirve (sus archivos eran de esa sesión).
    private func olvidarSimulacion() {
        controlSimulacion?.cancelar()
        controlCopia?.cancelar()
        controlBorrado?.cancelar()
        planBorrado = nil
        firmaPlan = nil
        if estadoBorrado == .revisado || estadoBorrado == .revisando { estadoBorrado = .nada }
        vistaPrevia = nil
        informeSimulacion = nil
        opcionesSimuladas = nil
        destinoSimulado = nil
        if estadoSimulacion != .simulando { estadoSimulacion = .nada }
        miniaturas.vaciar()
    }

    // MARK: Perfiles y cámaras

    func aplicar(_ p: Perfil) {
        opciones = p.opciones
        if let d = p.destino { destinoTexto = d }
        descomponerPeriodo()
        perfilElegido = p.nombre
        perfilAplicado = p
    }

    /// ¿Se ha cambiado algo desde que se aplicó el perfil? (Lo deducido al conectar no cuenta,
    /// y un perfil con «el rango que indiques» acepta cualquier rango.)
    var perfilModificado: Bool {
        guard let p = perfilAplicado, !perfilElegido.isEmpty else { return false }
        var guardadas = p.opciones.sinDeducciones
        let actuales = opciones.sinDeducciones
        if guardadas.periodo == .rangoPorIndicar, case .rango = actuales.periodo {
            guardadas.periodo = actuales.periodo
        }
        if guardadas != actuales { return true }
        if let d = p.destino, d != destinoTexto { return true }
        return false
    }

    /// Nombre (tal como está guardado) del perfil que ya se llama así, si existe.
    func perfilExistente(_ nombre: String) -> String? {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        return Perfiles.buscar(n)?.nombre
    }

    /// Guarda las opciones actuales con ese nombre. Devuelve el mensaje de confirmación
    /// («guardado» si es nuevo, «actualizado» si ya existía).
    @discardableResult
    func guardarComoPerfil(_ nombre: String) throws -> String {
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return "" }
        let existente = Perfiles.buscar(n)
        let nombreFinal = existente?.nombre ?? n
        var op = opciones.sinDeducciones
        // Un perfil «Viaje» sigue preguntando las fechas: no se fija el rango de esta vez.
        if let e = existente, e.opciones.periodo == .rangoPorIndicar, case .rango = op.periodo {
            op.periodo = .rangoPorIndicar
        }
        let p = Perfil(nombre: nombreFinal, opciones: op, destino: destinoTexto)
        let url = try Perfiles.guardar(p)
        perfiles = Perfiles.todos()
        perfilElegido = nombreFinal
        perfilAplicado = p
        let mensaje = existente == nil
            ? tr("Perfil «%@» guardado.", tr(nombreFinal))
            : tr("Perfil «%@» actualizado.", tr(nombreFinal))
        registrar("💾 " + mensaje + " (" + url.path + ")")
        return mensaje
    }

    /// Guarda los cambios en el perfil elegido.
    func actualizarPerfil() throws -> String {
        try guardarComoPerfil(perfilElegido)
    }

    /// Solo se borran los guardados. Un integrado actualizado tiene versión guardada:
    /// al borrarla, vuelve la integrada.
    var puedeBorrarPerfil: Bool {
        !perfilElegido.isEmpty && Perfiles.esGuardado(perfilElegido)
    }

    var perfilElegidoEsIntegrado: Bool {
        !perfilElegido.isEmpty && Perfiles.integrados.contains { $0.nombre == perfilElegido }
    }

    /// Borra el perfil elegido. Devuelve el mensaje de confirmación.
    func borrarPerfil() throws -> String {
        let nombre = perfilElegido
        try Perfiles.borrar(nombre)
        perfiles = Perfiles.todos()
        let mensaje: String
        if let integrado = Perfiles.integrados.first(where: { $0.nombre == nombre }) {
            aplicar(integrado)
            mensaje = tr("Se borró tu versión de «%@»: vuelve el perfil integrado.", tr(nombre))
        } else {
            perfilElegido = ""
            perfilAplicado = nil
            mensaje = tr("Perfil «%@» borrado.", nombre)
        }
        registrar("🗑 " + mensaje)
        return mensaje
    }

    /// Deduce el modelo de este iPhone de sus fotos recientes (lee unas pocas; luego usa la caché).
    private func deducirModelo(_ cat: Catalogo) async {
        deduciendoModelo = true
        defer { deduciendoModelo = false }
        let modelo = await EsteIPhone.deducir(cat, lector: LectorCamara())
        guard catalogo === cat else { return }
        modeloEsteIPhone = modelo
        if let modelo {
            registrar(tr("📱 Este iPhone: %@ (deducido de sus fotos recientes).", modelo))
        } else {
            registrar(tr("📱 No pude deducir el modelo de este iPhone (no encuentro fotos de su cámara)."))
        }
    }

    /// Lee la cámara de los elementos del periodo (la primera vez tarda; luego usa la caché).
    func detectarCamaras() async {
        guard let catalogo, !detectandoCamaras else { return }
        detectandoCamaras = true
        defer { detectandoCamaras = false }
        let lista = ListaCamaras(config: Configuracion(), catalogo: catalogo)
        lista.observador = { [weak self] evento in
            MainActor.assumeIsolated { self?.recibir(evento) }
        }
        camarasDetectadas = await lista.contar(en: opciones.periodo).filter { $0.modelo != nil }
    }

    /// Modelos que se pueden marcar: los detectados y los ya elegidos.
    var modelosDisponibles: [String] {
        var r = camarasDetectadas.compactMap(\.modelo)
        if let m = modeloEsteIPhone, !r.contains(m) { r.insert(m, at: 0) }
        for m in opciones.camaras ?? [] where !r.contains(m) { r.append(m) }
        return r
    }

    /// Captura de Imagen abierta hace que el iPhone entregue el catálogo; luego se reconecta.
    func abrirCapturaDeImagenYReconectar() async {
        alertaCapturaDeImagen = false
        await abrirCapturaDeImagen()
        await conectar()
    }

    private func descomponerPeriodo() {
        switch opciones.periodo {
        case .ultimosDias(let n):
            dias = n
        case .rango(let d, let h):
            // «El rango que indiques» (perfil Viaje): hoy, para que se elija en el calendario.
            let periodo = opciones.periodo
            desde = d ?? Calendar.current.startOfDay(for: Date())
            hasta = h ?? Date()
            opciones.periodo = periodo == .rangoPorIndicar ? rango : periodo
        case .todo, .mesAnterior:
            break
        }
    }

    private func guardarUltimaVez() {
        Perfiles.guardarUltima(Perfil(nombre: "ultima-vez", opciones: opciones, destino: destinoTexto))
    }

    private func recibir(_ evento: Evento) {
        switch evento {
        case .mensaje(let texto):
            registrar(texto)
        case .conexion(let estado):
            switch estado {
            case .buscando: fase = .buscando
            case .encontrado(let nombre): nombreIPhone = nombre
            case .esperando(_, let mensaje): fase = .esperando(mensaje)
            case .sesionAbierta:
                fase = .leyendoCatalogo(0)
                // Si a los 8 segundos sigue en 0 %, casi seguro falta Captura de Imagen abierta.
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    guard let self, self.fase == .leyendoCatalogo(0) else { return }
                    self.sugerirCapturaDeImagen = true
                }
            case .bloqueado: bloqueado = true
            case .desbloqueado: bloqueado = false
            case .catalogo(let p): if fase != .listo { fase = .leyendoCatalogo(p) }
            case .listo: break
            case .desconectado:
                fase = .desconectado
                olvidarSimulacion()
                catalogo = nil
                modeloEsteIPhone = nil
                camara = nil
            }
        case .inicio(let elementos, _):
            if enCopia { progreso.elementosTotal = elementos } else { simTotal = elementos }
        case .elemento(let indice, let total, let etiqueta):
            if enCopia {
                progreso.elementosHechos = indice - 1
                progreso.elementosTotal = total
            } else {
                simHechos = indice - 1
                simTotal = total
                simulacionEnCurso?.empezar(etiqueta)
            }
        case .archivo(let etiqueta, let archivo, let tipo, let resultado, let motivo):
            if enCopia {
                anotarCopia(etiqueta: etiqueta, archivo: archivo, resultado: resultado, motivo: motivo)
            } else {
                simulacionEnCurso?.agregar(etiqueta: etiqueta,
                                           ArchivoSimulado(archivo: archivo, tipo: tipo, resultado: resultado, motivo: motivo))
            }
        case .descarga(let nombre, let fraccion, let tamano):
            guard enCopia else { break }
            progreso.archivoActual = nombre
            progreso.fraccionActual = fraccion
            progreso.tamanoActual = tamano
            anotarVelocidad()
        case .borrando(let indice, let total, let etiqueta, let pendientes):
            borradoHechos = indice
            borradoTotal = total
            borradoActual = etiqueta
            if !pendientes.isEmpty {
                borradoFallos.append(tr("%@: sigue en el iPhone (%@)", etiqueta, pendientes.joined(separator: ", ")))
            }
        case .fin(let informe):
            if enCopia {
                progreso.elementosHechos = progreso.elementosTotal
                informeCopia = informe
            } else {
                simHechos = simTotal
                informeSimulacion = informe
            }
        default:
            break
        }
    }

    private func anotarCopia(etiqueta: String, archivo: Archivo, resultado: Resultado, motivo: String) {
        switch resultado {
        case .copiado, .copiadoConAviso:
            progreso.copiados += 1
            if resultado == .copiadoConAviso {
                progreso.conAviso += 1
                progreso.errores.append("⚠️ \(archivo.nombre): \(motivo)")
            }
            progreso.bytesHechos += archivo.tamano
        case .yaExistia: progreso.yaExistian += 1
        case .reubicado: progreso.movidos += 1
        case .descartado: progreso.descartados += 1
        case .error, .noEncontrado:
            progreso.errores.append("✗ \(archivo.nombre): \(motivo)")
            registrar(tr("✗ %@: %@", archivo.nombre, motivo))
        case .seCopiaria, .seReubicaria:
            break
        }
        progreso.archivoActual = nil
        progreso.fraccionActual = 0
        progreso.tamanoActual = 0
        anotarVelocidad()
    }

    private func registrar(_ texto: String) {
        let t = texto.trimmingCharacters(in: .newlines)
        guard !t.isEmpty else { return }
        mensajes.append(t)
        if mensajes.count > 500 { mensajes.removeFirst(mensajes.count - 500) }
    }
}
