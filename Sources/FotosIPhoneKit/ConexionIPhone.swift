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

    public override init() {
        super.init()
    }

    @MainActor
    public func conectar(segundos: TimeInterval = 120) async throws -> ICCameraDevice {
        try await withCheckedThrowingContinuation { cont in
            espera = cont
            navegador.delegate = self
            let mascara = ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue
            navegador.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mascara)!
            print(tr("🔌 Buscando el iPhone por USB…"))
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

    public func cerrar() {
        camara?.requestCloseSession()
        navegador.stop()
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
                print(tr("   (ignorando «%@», no es un iPhone)", nombre))
                return
            }
            camara = cam
            print(tr("📱 Encontrado: %@. Abriendo sesión…", nombre))
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
                print(tr("\n⚠️  El iPhone se desconectó. Vuelve a conectarlo y ejecuta el mismo comando: lo ya copiado se salta."))
                exit(3)
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
                if reintentos == 1 {
                    print(tr("🔒 El iPhone respondió: %@", error.localizedDescription))
                    print(tr("   · Deja el iPhone desbloqueado y con la pantalla encendida (no en la pantalla de bloqueo)."))
                    print(tr("   · Si aparece «¿Confiar en este ordenador?», toca Confiar e introduce el código."))
                    print(tr("   Reintentando cada 3 segundos…"))
                } else if reintentos % 5 == 0 {
                    print(tr("   … sigo esperando (%ld intentos)", reintentos))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.espera != nil, self.camara === cam else { return }
                    cam.requestOpenSession()
                }
                return
            }
            limite?.invalidate(); limite = nil
            print(tr("🔓 Sesión abierta. Leyendo el catálogo (con bibliotecas grandes puede tardar)…"))
            if let cam = device as? ICCameraDevice, cam.isAccessRestrictedAppleDevice {
                print(tr("🔒 Desbloquea el iPhone para continuar."))
            }
            avisoCatalogo = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let cam = self?.camara else { return }
                print(tr("   catálogo: %ld %%", Int(cam.contentCatalogPercentCompleted)))
            }
        }
    }

    public func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    // MARK: ICCameraDeviceDelegate

    public func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        DispatchQueue.main.async { [self] in
            print(tr("✅ Catálogo completo."))
            terminar(.success(device))
        }
    }

    public func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print(tr("🔒 El iPhone está bloqueado: desbloquéalo para continuar."))
    }

    public func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        print(tr("🔓 iPhone desbloqueado."))
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

/// Caja para compartir el progreso de una descarga con el temporizador que lo muestra.
private final class EstadoDescarga: @unchecked Sendable {
    var progreso: Progress?
    var aviso: Timer?
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
    @MainActor
    func descargar(en carpeta: URL, como nombre: String) async throws -> URL {
        let estado = EstadoDescarga()
        defer { estado.aviso?.invalidate() }
        let grande = Int64(fileSize) > 200_000_000

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
            if grande {
                estado.aviso = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    if let p = estado.progreso {
                        print(String(format: "        … %.0f %%", p.fractionCompleted * 100))
                    }
                }
            }
        }
    }
}
