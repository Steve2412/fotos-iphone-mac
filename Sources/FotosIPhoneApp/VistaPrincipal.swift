import SwiftUI
import AppKit
import FotosCore

/// Ventana principal: opciones a la izquierda; a la derecha, estado del iPhone, catálogo y registro.
/// Debajo del resumen, la simulación con su vista previa y, al copiar, el progreso de la copia.
struct VistaPrincipal: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var verRegistro = true

    var body: some View {
        @Bindable var modelo = modelo
        NavigationSplitView {
            PanelOpciones()
                .disabled(modelo.ocupado)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
        } detail: {
            detalle
        }
        // Al abrir la app sin Captura de Imagen: se explica y se abre.
        .alert(tr("Hace falta Captura de Imagen"), isPresented: $modelo.pedirCapturaAlInicio) {
            Button(tr("Abrir Captura de Imagen")) {
                Task { await modelo.abrirCapturaDeImagenYConectar() }
            }
            Button(tr("Salir"), role: .cancel) { NSApp.terminate(nil) }
        } message: {
            Text(tr("Para que el Mac pueda ver las fotos del iPhone, Captura de Imagen tiene que estar abierta. Sin ella, esta app no podrá detectar ni copiar nada.\n\nSe abrirá ahora en segundo plano: déjala abierta mientras usas esta app."))
        }
        // No llegan las fotos: lo más seguro es salir, abrir Captura de Imagen y volver a abrir la app.
        .alert(tr("No se detectan las fotos"), isPresented: $modelo.alertaCapturaDeImagen) {
            Button(tr("Salir de la app")) { NSApp.terminate(nil) }
            Button(tr("Abrir Captura de Imagen y reconectar")) {
                Task { await modelo.abrirCapturaDeImagenYReconectar() }
            }
            Button(tr("Seguir esperando"), role: .cancel) {}
        } message: {
            Text(tr("El iPhone no está entregando sus fotos. Normalmente se arregla así: cierra esta app, abre Captura de Imagen (en Aplicaciones), espera a que muestre el iPhone y vuelve a abrir esta app."))
        }
    }

    private var detalle: some View {
        VStack(spacing: 0) {
            BarraEstado()
            if modelo.sugerirCapturaDeImagen {
                AvisoCapturaDeImagen()
            }
            Divider()
            if modelo.catalogo != nil {
                SelectorSeccion()
            }
            Group {
                if modelo.catalogo != nil && modelo.seccion == .borrar {
                    ScrollView {
                        PanelBorrado()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if let catalogo = modelo.catalogo {
                    ScrollView {
                        VStack(spacing: 20) {
                            ResumenCatalogo(catalogo: catalogo)
                            if modelo.estadoCopia != .nada {
                                PanelCopia()
                            }
                            if !modelo.copiando {
                                if modelo.vistaPrevia == nil && modelo.estadoCopia == .nada {
                                    ResumenOpciones()
                                }
                                PanelSimulacion()
                            }
                        }
                    }
                } else {
                    EsperaConexion()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            DisclosureGroup(isExpanded: $verRegistro) {
                Registro()
            } label: {
                Text(tr("Registro")).font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: Sección

/// Copiar al Mac o borrar del iPhone.
struct SelectorSeccion: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        @Bindable var modelo = modelo
        Picker(tr("Sección"), selection: $modelo.seccion) {
            Label(tr("Copiar al Mac"), systemImage: "arrow.down.to.line").tag(ModeloApp.Seccion.copiar)
            Label(tr("Borrar del iPhone"), systemImage: "trash").tag(ModeloApp.Seccion.borrar)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .disabled(modelo.ocupado)
        .padding(.vertical, 8)
    }
}

// MARK: Barra de estado

struct BarraEstado: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icono)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline)
                Text(detalle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if modelo.bloqueado {
                Label(tr("Bloqueado"), systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if case .leyendoCatalogo(let p) = modelo.fase {
                ProgressView(value: Double(p), total: 100)
                    .frame(width: 180)
            }
            if modelo.conectando {
                Button(tr("Detener")) { modelo.detenerConexion() }
                    .help(tr("Deja de intentar conectar; luego puedes pulsar Reconectar."))
            }
            if puedeReconectar && !modelo.ocupado {
                Button(tr("Reconectar")) {
                    Task { await modelo.conectar() }
                }
            }
        }
        .padding(12)
    }

    private var puedeReconectar: Bool {
        switch modelo.fase {
        case .listo, .desconectado, .detenido, .error: return true
        default: return false
        }
    }

    private var icono: String {
        switch modelo.fase {
        case .buscando: return "cable.connector"
        case .esperando: return "lock.iphone"
        case .leyendoCatalogo: return "arrow.down.circle"
        case .listo: return "iphone"
        case .desconectado: return "cable.connector.slash"
        case .detenido: return "pause.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch modelo.fase {
        case .listo: return .green
        case .error, .desconectado: return .red
        case .esperando: return .orange
        default: return .accentColor
        }
    }

    private var titulo: String {
        switch modelo.fase {
        case .buscando: return tr("Buscando el iPhone…")
        case .esperando: return tr("Esperando al iPhone")
        case .leyendoCatalogo(let p): return tr("Leyendo el catálogo… %ld %%", p)
        case .listo: return modelo.nombreIPhone ?? "iPhone"
        case .desconectado: return tr("iPhone desconectado")
        case .detenido: return tr("Conexión detenida")
        case .error: return tr("No se pudo conectar")
        }
    }

    private var detalle: String {
        switch modelo.fase {
        case .buscando:
            return tr("Conéctalo por cable y desbloquéalo.")
        case .esperando(let m):
            return tr("Desbloquéalo y acepta «Confiar en este ordenador». (%@)", m)
        case .leyendoCatalogo:
            return modelo.nombreIPhone.map { tr("%@ · con bibliotecas grandes puede tardar", $0) } ?? ""
        case .listo:
            return tr("%ld archivos en el iPhone", modelo.catalogo?.cantidadArchivos ?? 0)
        case .desconectado:
            return tr("Vuelve a conectarlo y pulsa Reconectar.")
        case .detenido:
            return tr("Pulsa Reconectar cuando quieras volver a intentarlo.")
        case .error(let m):
            return m
        }
    }
}

// MARK: Avisos

/// El catálogo no avanza: falta Captura de Imagen abierta (requisito de macOS con el iPhone).
struct AvisoCapturaDeImagen: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(tr("No se detectan las fotos. Cierra esta app, abre Captura de Imagen y vuelve a abrir la app."))
                .font(.callout)
            Spacer()
            Button(tr("Abrir Captura de Imagen y reconectar")) {
                Task { await modelo.abrirCapturaDeImagenYReconectar() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}

// MARK: Contenido

struct EsperaConexion: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(spacing: 12) {
            if case .detenido = modelo.fase {
                Image(systemName: "pause.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            } else if case .error = modelo.fase {
                Image(systemName: "iphone.slash").font(.system(size: 48)).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
            Text(tr("Antes de empezar")).font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("· Captura de Imagen abierta en el Mac."))
                Text(tr("· iPhone conectado por cable, desbloqueado y con el bloqueo automático en «Nunca»."))
                Text(tr("· En el iPhone: Ajustes → Apps → Fotos → Transferir a Mac o PC → «Conservar originales»."))
                Text(tr("· Fotos cerrada en el Mac."))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

/// Resumen de lo que hay en el iPhone (sin leer metadatos: solo lo que da el catálogo).
struct ResumenCatalogo: View {
    let catalogo: Catalogo

    var body: some View {
        let elementos = catalogo.todosLosElementos
        let fotos = elementos.filter { $0.imagenOriginal != nil }.count
        let videos = elementos.filter { $0.imagenOriginal == nil && $0.videoOriginal != nil }.count
        let otrasApps = catalogo.otrosElementos.count
        let bytes = catalogo.archivos.reduce(Int64(0)) { $0 + $1.tamano }
        let fechas = elementos.compactMap(\.fecha)

        VStack(spacing: 24) {
            HStack(spacing: 16) {
                Cifra(valor: "\(fotos)", nombre: tr("fotos"))
                Cifra(valor: "\(videos)", nombre: tr("vídeos"))
                Cifra(valor: "\(otrasApps)", nombre: tr("de otras apps"))
                Cifra(valor: formatoBytes(bytes), nombre: tr("en total"))
            }
            if let primera = fechas.min(), let ultima = fechas.max() {
                Text(tr("Desde %@ hasta %@", formatoFecha(primera), formatoFecha(ultima)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
    }
}

/// Lo que se va a hacer con las opciones del panel (lo mismo que muestra la Terminal).
struct ResumenOpciones: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("⚙️  Opciones:")).font(.headline)
            ForEach(modelo.opciones.resumen, id: \.self) { linea in
                Text("· " + linea)
            }
            Text("· " + tr("Destino: %@", modelo.destinoURL.path))
                .foregroundStyle(modelo.destinoValido ? Color.primary : Color.red)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 28)
    }
}

struct Cifra: View {
    let valor: String
    let nombre: String

    var body: some View {
        VStack(spacing: 4) {
            Text(valor).font(.system(size: 28, weight: .semibold, design: .rounded))
            Text(nombre).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 120)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Registro

struct Registro: View {
    @Environment(ModeloApp.self) private var modelo

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(modelo.mensajes.enumerated()), id: \.offset) { i, m in
                        Text(m)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(6)
            }
            .frame(height: 150)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: modelo.mensajes.count) {
                lector.scrollTo(modelo.mensajes.count - 1, anchor: .bottom)
            }
        }
    }
}
