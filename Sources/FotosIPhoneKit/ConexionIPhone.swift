import Foundation
import CoreGraphics
import ImageCaptureCore
import FotosCore

/// Localiza el iPhone por USB, abre una sesión de solo lectura y espera a que
/// el teléfono termine de enviar su catálogo de archivos.
/// Todo su estado se toca solo desde el hilo principal (los avisos se reenvían con DispatchQueue.main).
public final class ConexionIPhone: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate, @unchecked Sendable {
    private let navegador = ICDeviceBrowser()
    private(set) var camara: ICCameraDevice?
    private var espera: CheckedContinuation<ICCameraDevice, Error>?
    private var limite: Timer?
    private var avisoCatalogo: Timer?
    private var reintentos = 0
    private var ultimoError: String?
    private var ticsCatalogo = 0
    /// Quién recibe los avisos (la Terminal los imprime; la app actualiza su estado).
    public var observador: Observador = Observadores.terminal

    public override init() {
        super.init()
    }

    private func avisar(_ e: Evento) { observador(e) }
    private func decir(_ texto: String) { observador(.mensaje(texto)) }

    @MainActor
    public func conectar(segundos: TimeInterval = 120) async throws -> ICCameraDevice {
        try await withCheckedThrowingContinuation { cont in
            espera = cont
            navegador.delegate = self
            let mascara = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
            navegador.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mascara)!
            avisar(.conexion(.buscando))
            decir(tr("🔌 Buscando el iPhone por USB…"))
            navegador.start()
            limite = Timer.scheduledTimer(withTimeInterval: segundos, repeats: false) { [weak self] _ in
                guard let self else { return }
                if self.camara == nil {
                    self.terminar(.failure(ErrorHerramienta.sinIPhone))
                } else if let e = self.ultimoError {
                    self.terminar(.failure(ErrorHerramienta.sesion(e)))
                } else {
                    self.terminar(.failure(ErrorHerramienta.sinRespuesta))
                }
            }
        }
    }

    /// Cierra la sesión. Si todavía se estaba conectando, `conectar` termina con `.cancelado`.
    public func cerrar() {
        camara?.requestCloseSession()
        navegador.stop()
        terminar(.failure(ErrorHerramienta.cancelado))
    }

    private func terminar(_ resultado: Result<ICCameraDevice, Error>) {
        limite?.invalidate(); limite = nil
        avisoCatalogo?.invalidate(); avisoCatalogo = nil
        guard let e = espera else { return }
        espera = nil
        e.resume(with: resultado)
    }

    // MARK: ICDeviceBrowserDelegate

    public func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        DispatchQueue.main.async { [self] in
            guard camara == nil, let cam = device as? ICCameraDevice else { return }
            let nombre = device.name ?? tr("dispositivo")
            let tipo = device.productKind ?? ""
            guard tipo.localizedCaseInsensitiveContains("iPhone") || nombre.localizedCaseInsensitiveContains("iPhone") else {
                decir(tr("   (ignorando «%@», no es un iPhone)", nombre))
                return
            }
            camara = cam
            avisar(.conexion(.encontrado(nombre: nombre)))
            decir(tr("📱 Encontrado: %@. Abriendo sesión…", nombre))
            cam.delegate = self
            cam.requestOpenSession()
        }
    }

    public func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        DispatchQueue.main.async { [self] in
            guard let cam = camara, device === cam else { return }
            if espera != nil {
                terminar(.failure(ErrorHerramienta.sinIPhone))
            } else {
                // La Terminal termina el programa al recibir .desconectado; la app lo muestra.
                decir(tr("\n⚠️  El iPhone se desconectó. Vuelve a conectarlo y ejecuta el mismo comando: lo ya copiado se salta."))
                avisar(.conexion(.desconectado))
            }
        }
    }

    // MARK: ICDeviceDelegate

    public func didRemove(_ device: ICDevice) {}

    public func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        DispatchQueue.main.async { [self] in
            if let error {
                // El iPhone rechaza la sesión mientras está bloqueado o no ha terminado de
                // confiar en este Mac. Se reintenta hasta que se agote el tiempo límite.
                guard espera != nil, let cam = device as? ICCameraDevice else { return }
                ultimoError = error.localizedDescription
                reintentos += 1
                avisar(.conexion(.esperando(intentos: reintentos, mensaje: error.localizedDescription)))
                if reintentos == 1 {
                    decir(tr("🔒 El iPhone respondió: %@", error.localizedDescription))
                    decir(tr("   · Deja el iPhone desbloqueado y con la pantalla encendida (no en la pantalla de bloqueo)."))
                    decir(tr("   · Si aparece «¿Confiar en este ordenador?», toca Confiar e introduce el código."))
                    decir(tr("   Reintentando cada 3 segundos…"))
                } else if reintentos % 5 == 0 {
                    decir(tr("   … sigo esperando (%ld intentos)", reintentos))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.espera != nil, self.camara === cam else { return }
                    cam.requestOpenSession()
                }
                return
            }
            limite?.invalidate(); limite = nil
            avisar(.conexion(.sesionAbierta))
            decir(tr("🔓 Sesión abierta. Leyendo el catálogo (con bibliotecas grandes puede tardar)…"))
            if let cam = device as? ICCameraDevice, cam.isAccessRestrictedAppleDevice {
                avisar(.conexion(.bloqueado))
                decir(tr("🔒 Desbloquea el iPhone para continuar."))
            }
            // El porcentaje se avisa cada segundo (la app lo muestra), pero se imprime cada 5.
            ticsCatalogo = 0
            avisoCatalogo = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let cam = self.camara else { return }
                let porcentaje = Int(cam.contentCatalogPercentCompleted)
                self.avisar(.conexion(.catalogo(porcentaje: porcentaje)))
                self.ticsCatalogo += 1
                if self.ticsCatalogo % 5 == 0 { self.decir(tr("   catálogo: %ld %%", porcentaje)) }
            }
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    // MARK: ICCameraDeviceDelegate

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        DispatchQueue.main.async { [self] in
            avisar(.conexion(.listo))
            decir(tr("✅ Catálogo completo."))
            terminar(.success(device))
        }
    }

    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        DispatchQueue.main.async { [self] in
            avisar(.conexion(.bloqueado))
            decir(tr("🔒 El iPhone está bloqueado: desbloquéalo para continuar."))
        }
    }

    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        DispatchQueue.main.async { [self] in
            avisar(.conexion(.desbloqueado))
            decir(tr("🔓 iPhone desbloqueado."))
        }
    }

    // (La sesión se reintenta desde device(_:didOpenSessionWithError:).)

    public func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    public func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    public func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    public func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
}

/// Caja para compartir el progreso de una descarga con el temporizador que lo avisa.
private final class EstadoDescarga: @unchecked Sendable {
    var progreso: Progress?
    var aviso: Timer?
    var alProgresar: ((Double) -> Void)?
}

extension ICCameraFile {
    /// Metadatos (EXIF, TIFF, GPS…) leídos del iPhone sin descargar el archivo.
    @MainActor
    func leerMetadatos() async throws -> [AnyHashable: Any] {
        try await withCheckedThrowingContinuation { cont in
            requestMetadataDictionary(options: [:]) { dic, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: dic ?? [:])
                }
            }
        }
    }

    /// Copia el archivo tal cual (byte a byte) a `carpeta` con el nombre indicado.
    /// `alProgresar` recibe el avance (0…1) cada segundo mientras dura la descarga.
    @MainActor
    func descargar(en carpeta: URL, como nombre: String,
                   alProgresar: ((Double) -> Void)? = nil) async throws -> URL {
        let estado = EstadoDescarga()
        estado.alProgresar = alProgresar
        defer { estado.aviso?.invalidate() }

        return try await withCheckedThrowingContinuation { cont in
            let opciones: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: carpeta,
                .saveAsFilename: nombre,
                .overwrite: true,
            ]
            estado.progreso = requestDownload(options: opciones) { archivo, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: carpeta.appendingPathComponent(archivo ?? nombre))
                }
            }
            if estado.alProgresar != nil {
                estado.aviso = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    if let p = estado.progreso { estado.alProgresar?(p.fractionCompleted) }
                }
            }
        }
    }
}
