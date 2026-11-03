import SwiftUI
import AppKit
import FotosCore

/// App de Mac sobre la misma biblioteca que la herramienta de Terminal.
/// Se monta como «Fotos iPhone.app» con ./empaquetar-app.sh.
@main
struct FotosIPhoneApp: App {
    @NSApplicationDelegateAdaptor(Delegado.self) private var delegado
    @State private var modelo = ModeloApp()

    /// El idioma elegido en Ajustes al abrir la app ("" = el del sistema).
    static let idiomaAlArrancar = UserDefaults.standard.string(forKey: "idioma") ?? ""

    init() {
        // Idioma: el elegido en Ajustes o, si no hay, el del sistema.
        let elegido = Self.idiomaAlArrancar
        Idioma.elegir(elegido.isEmpty ? nil : elegido)
    }

    var body: some Scene {
        WindowGroup(tr("Fotos iPhone")) {
            VistaPrincipal()
                .environment(modelo)
                .frame(minWidth: 820, minHeight: 540)
                .background(AccesoVentana { delegado.vigilar($0) })
                .task {
                    delegado.modelo = modelo
                    // Si se cierra la ventana y se abre otra, no se reconecta (podría haber una copia en curso).
                    await modelo.iniciar()
                }
        }
        Settings {
            VistaAjustes()
                .environment(modelo)
        }
    }
}

/// Cerrar la ventana es salir de la app (como ⌘Q). Con una copia o un borrado en curso,
/// se pide confirmación y se recomienda no salir.
@MainActor
final class Delegado: NSObject, NSApplicationDelegate {
    weak var modelo: ModeloApp?
    /// Ya se confirmó la salida (al cerrar la ventana): no se vuelve a preguntar.
    private var salidaConfirmada = false
    /// Vigilantes de cada ventana (se guardan aquí para que no se liberen).
    private var vigilantes: [ObjectIdentifier: VigilanteVentana] = [:]

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        salidaConfirmada || confirmarSalida() ? .terminateNow : .terminateCancel
    }

    /// true si se puede salir: no hay nada en curso o el usuario insiste.
    func confirmarSalida() -> Bool {
        guard let modelo, modelo.copiando || modelo.borrando else { return true }
        let alerta = NSAlert()
        alerta.alertStyle = .warning
        if modelo.borrando {
            alerta.messageText = tr("Se está borrando del iPhone")
            alerta.informativeText = tr("Es mejor no salir para que el borrado pueda terminar. Si sales ahora, el elemento en curso puede quedar a medias; lo demás no se toca.")
            alerta.addButton(withTitle: tr("Seguir borrando (recomendado)"))
        } else {
            alerta.messageText = tr("Hay una copia en curso")
            alerta.informativeText = tr("Es mejor no salir para que la copia pueda continuar. Si sales ahora, se pierde el archivo que se está descargando; lo ya copiado se queda en el destino y, la próxima vez, se salta.")
            alerta.addButton(withTitle: tr("Seguir copiando (recomendado)"))
        }
        alerta.addButton(withTitle: tr("Salir de todos modos"))
        let salir = alerta.runModal() == .alertSecondButtonReturn
        if salir { salidaConfirmada = true }
        return salir
    }

    /// Pone el vigilante en la ventana (si SwiftUI cambió su delegado, se vuelve a poner).
    func vigilar(_ ventana: NSWindow) {
        guard !(ventana.delegate is VigilanteVentana) else { return }
        let v = VigilanteVentana(original: ventana.delegate, app: self)
        vigilantes[ObjectIdentifier(ventana)] = v
        ventana.delegate = v
    }
}

/// Delegado de la ventana que pregunta antes de cerrarla y pasa todo lo demás
/// al delegado que puso SwiftUI. (AppKit lo llama siempre en el hilo principal.)
final class VigilanteVentana: NSObject, NSWindowDelegate {
    private let original: NSWindowDelegate?
    private weak var app: Delegado?

    init(original: NSWindowDelegate?, app: Delegado) {
        self.original = original
        self.app = app
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if original?.windowShouldClose?(sender) == false { return false }
            return app?.confirmarSalida() ?? true
        }
    }
}

/// Da acceso a la ventana de SwiftUI.
struct AccesoVentana: NSViewRepresentable {
    let alTener: (NSWindow) -> Void

    func makeNSView(context: Context) -> VistaConVentana {
        let v = VistaConVentana()
        v.alTener = alTener
        return v
    }

    func updateNSView(_ v: VistaConVentana, context: Context) {
        if let w = v.window { alTener(w) }
    }
}

final class VistaConVentana: NSView {
    var alTener: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let w = window { alTener?(w) }
    }
}
