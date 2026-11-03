import SwiftUI
import AppKit
import FotosCore

/// Ajustes (⌘,): el idioma de la app. Se guarda en las preferencias y se aplica al volver a abrirla.
struct VistaAjustes: View {
    @Environment(ModeloApp.self) private var modelo
    /// "" = el idioma del sistema.
    @AppStorage("idioma") private var idioma = ""

    var body: some View {
        Form {
            Picker(tr("Idioma"), selection: $idioma) {
                Text(tr("El del sistema")).tag("")
                ForEach(Idioma.disponibles, id: \.self) { codigo in
                    Text(nombre(codigo)).tag(codigo)
                }
            }
            if idioma != FotosIPhoneApp.idiomaAlArrancar {
                Text(tr("El cambio se aplica al volver a abrir la app."))
                    .font(.callout).foregroundStyle(.secondary)
                Button(tr("Volver a abrir ahora")) { reabrir() }
                    .disabled(modelo.ocupado)
                if modelo.ocupado {
                    Text(tr("Espera a que termine la copia o el borrado."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(tr("La herramienta de Terminal usa --idioma (o --language)."))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    /// «español», «English»… cada uno en su propio idioma.
    private func nombre(_ codigo: String) -> String {
        let n = Locale(identifier: codigo).localizedString(forLanguageCode: codigo) ?? codigo
        return n.prefix(1).uppercased() + n.dropFirst()
    }

    /// Abre otra vez la app (un segundo después de salir) para aplicar el idioma.
    private func reabrir() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
