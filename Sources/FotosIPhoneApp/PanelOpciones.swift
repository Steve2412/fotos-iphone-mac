import SwiftUI
import AppKit
import FotosCore
import FotosIPhoneKit

/// Panel izquierdo: qué copiar y adónde. Las mismas opciones que el asistente de Terminal.
struct PanelOpciones: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var pidiendoNombre = false
    @State private var nombrePerfil = ""
    @State private var errorPerfil: String?
    /// Confirmación tras guardar, actualizar o borrar un perfil.
    @State private var avisoPerfil: String?
    @State private var confirmandoSustituir: String?
    @State private var confirmandoBorrar = false
    @State private var textoVideoMax = ""

    var body: some View {
        @Bindable var modelo = modelo
        Form {
            // Perfil
            Section(tr("Perfil")) {
                Picker(tr("Partir de"), selection: perfilBinding) {
                    Text(tr("A mano")).tag("")
                    ForEach(modelo.perfiles, id: \.nombre) { p in
                        Text(p.nombreVisible).tag(p.nombre)
                    }
                }
                if modelo.perfilModificado {
                    Text(tr("Has cambiado opciones de este perfil."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    if modelo.perfilModificado {
                        Button(tr("Actualizar «%@»", tr(modelo.perfilElegido))) {
                            hacer { try modelo.actualizarPerfil() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button(tr("Guardar como perfil…")) {
                        nombrePerfil = modelo.perfilElegido.isEmpty ? "" : tr(modelo.perfilElegido)
                        pidiendoNombre = true
                    }
                    if modelo.puedeBorrarPerfil {
                        Button(modelo.perfilElegidoEsIntegrado ? tr("Volver al original") : tr("Borrar perfil"),
                               role: .destructive) {
                            confirmandoBorrar = true
                        }
                    }
                }
                if !modelo.perfilElegido.isEmpty && !modelo.puedeBorrarPerfil {
                    Text(tr("Perfil integrado: no se puede borrar."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Periodo
            Section(tr("Periodo")) {
                Picker(tr("Periodo"), selection: $modelo.tipoPeriodo) {
                    Text(tr("Todo el iPhone")).tag(ModeloApp.TipoPeriodo.todo)
                    Text(tr("Los últimos días")).tag(ModeloApp.TipoPeriodo.ultimosDias)
                    Text(tr("El mes pasado (%@)", Opciones.Periodo.textoMesAnterior())).tag(ModeloApp.TipoPeriodo.mesAnterior)
                    Text(tr("Entre dos fechas")).tag(ModeloApp.TipoPeriodo.rango)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                switch modelo.tipoPeriodo {
                case .ultimosDias:
                    Stepper(value: $modelo.dias, in: 1...3650) {
                        Text(tr("%ld días (hoy incluido)", modelo.dias))
                    }
                case .rango:
                    DatePicker(tr("Desde"), selection: $modelo.desde, displayedComponents: .date)
                    DatePicker(tr("Hasta"), selection: $modelo.hasta, in: modelo.desde..., displayedComponents: .date)
                case .todo, .mesAnterior:
                    EmptyView()
                }
            }

            // Orígenes y cámaras
            Section(tr("Qué incluir")) {
                ForEach(Opciones.Origen.allCases, id: \.self) { o in
                    Toggle(o.texto, isOn: origen(o))
                }
                if modelo.opciones.origenes.isEmpty {
                    Text(tr("Elige al menos un origen.")).foregroundStyle(.red).font(.caption)
                }
            }
            if modelo.opciones.origenes.contains(.camara) {
                Section(tr("Cámaras")) {
                    Picker(tr("Cámaras"), selection: $modelo.tipoCamara) {
                        Text(textoEsteIPhone).tag(ModeloApp.TipoCamara.esteIPhone)
                        Text(tr("De cualquier cámara")).tag(ModeloApp.TipoCamara.cualquiera)
                        Text(tr("Elegir cámaras")).tag(ModeloApp.TipoCamara.elegir)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    if modelo.tipoCamara == .esteIPhone {
                        if modelo.deduciendoModelo {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(tr("Deduciendo el modelo de sus fotos recientes…")).font(.caption)
                            }
                        } else if modelo.catalogo != nil && modelo.modeloEsteIPhone == nil {
                            Text(tr("No pude deducir el modelo (no hay fotos de su cámara). Elige las cámaras a mano."))
                                .foregroundStyle(.red).font(.caption)
                        }
                    }
                    if modelo.tipoCamara == .elegir {
                        ForEach(modelo.modelosDisponibles, id: \.self) { m in
                            Toggle(isOn: camara(m)) {
                                Text(etiquetaCamara(m))
                            }
                        }
                        if modelo.opciones.camaras?.isEmpty ?? false {
                            Text(tr("Elige al menos una cámara.")).foregroundStyle(.red).font(.caption)
                        }
                        HStack {
                            Button(tr("Detectar cámaras del periodo")) {
                                Task { await modelo.detectarCamaras() }
                            }
                            .disabled(modelo.catalogo == nil || modelo.detectandoCamaras)
                            if modelo.detectandoCamaras { ProgressView().controlSize(.small) }
                        }
                        Text(tr("La primera vez tarda: lee la cámara de cada foto. Después lo recuerda."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Versiones y vídeos
            Section(tr("Ediciones")) {
                Picker(tr("Versión"), selection: $modelo.opciones.versiones) {
                    ForEach(Opciones.Versiones.allCases, id: \.self) { v in
                        Text(v.texto).tag(v)
                    }
                }
                if modelo.opciones.versiones == .originalYEditada {
                    Toggle(tr("Instrucciones de edición (.AAE)"), isOn: $modelo.opciones.aae)
                }
            }
            Section(tr("Vídeos")) {
                Toggle(tr("Incluir vídeos"), isOn: $modelo.opciones.videos)
                if modelo.opciones.videos {
                    TextField(tr("Tamaño máximo"), text: $textoVideoMax, prompt: Text(tr("sin límite (p. ej. 2GB)")))
                        .onSubmit { aplicarVideoMax() }
                        .onChange(of: textoVideoMax) { aplicarVideoMax() }
                    if !textoVideoMax.isEmpty && Opciones.bytes(textoVideoMax) == nil {
                        Text(tr("No entiendo ese tamaño. Ejemplos: 2GB, 500MB.")).foregroundStyle(.red).font(.caption)
                    }
                }
                Toggle(tr("Vídeos de las Live Photos"), isOn: $modelo.opciones.videosLivePhoto)
            }
            Section(tr("RAW y carpetas")) {
                Picker(tr("Fotos RAW (DNG)"), selection: $modelo.opciones.raw) {
                    ForEach(Opciones.ModoRAW.allCases, id: \.self) { r in
                        Text(r.texto).tag(r)
                    }
                }
                Picker(tr("Organización"), selection: $modelo.opciones.organizacion) {
                    ForEach(Opciones.Organizacion.allCases, id: \.self) { o in
                        Text(o.texto).tag(o)
                    }
                }
            }

            // Destino
            Section(tr("Destino")) {
                HStack {
                    TextField(tr("Carpeta"), text: $modelo.destinoTexto)
                    Button(tr("Elegir…")) { elegirCarpeta() }
                }
                if !modelo.destinoValido {
                    Text(tr("No se puede escribir en esa carpeta."))
                        .foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            textoVideoMax = modelo.opciones.videoMaximo.map { formatoBytes($0) } ?? ""
        }
        .onChange(of: modelo.perfilElegido) {
            textoVideoMax = modelo.opciones.videoMaximo.map { formatoBytes($0) } ?? ""
        }
        .alert(tr("Guardar como perfil"), isPresented: $pidiendoNombre) {
            TextField(tr("Nombre"), text: $nombrePerfil)
            Button(tr("Guardar")) {
                if let existente = modelo.perfilExistente(nombrePerfil) {
                    // Ya existe: se pide confirmación antes de sustituirlo.
                    confirmandoSustituir = existente
                } else {
                    hacer { try modelo.guardarComoPerfil(nombrePerfil) }
                }
            }
            Button(tr("Cancelar"), role: .cancel) {}
        } message: {
            Text(tr("Se guardan las opciones y la carpeta de destino. También estará disponible en Terminal con --perfil."))
        }
        .alert(tr("¿Actualizar el perfil «%@»?", tr(confirmandoSustituir ?? "")),
               isPresented: Binding(get: { confirmandoSustituir != nil }, set: { if !$0 { confirmandoSustituir = nil } })) {
            Button(tr("Actualizar")) {
                let n = confirmandoSustituir ?? ""
                confirmandoSustituir = nil
                hacer { try modelo.guardarComoPerfil(n) }
            }
            Button(tr("Cancelar"), role: .cancel) { confirmandoSustituir = nil }
        } message: {
            Text(tr("Ya existe un perfil con ese nombre. Sus opciones se sustituirán por las actuales."))
        }
        .confirmationDialog(modelo.perfilElegidoEsIntegrado
                                ? tr("¿Volver al perfil «%@» original?", tr(modelo.perfilElegido))
                                : tr("¿Borrar el perfil «%@»?", tr(modelo.perfilElegido)),
                            isPresented: $confirmandoBorrar) {
            Button(modelo.perfilElegidoEsIntegrado ? tr("Borrar mis cambios") : tr("Borrar"), role: .destructive) {
                hacer { try modelo.borrarPerfil() }
            }
            Button(tr("Cancelar"), role: .cancel) {}
        } message: {
            Text(modelo.perfilElegidoEsIntegrado
                 ? tr("Se borra tu versión guardada y vuelve la que trae la app.")
                 : tr("Se borra el archivo del perfil. Las fotos ya copiadas no se tocan."))
        }
        .alert(avisoPerfil ?? "", isPresented: Binding(get: { avisoPerfil != nil }, set: { if !$0 { avisoPerfil = nil } })) {
            Button("OK") { avisoPerfil = nil }
        }
        .alert(tr("No se pudo guardar el perfil"), isPresented: Binding(get: { errorPerfil != nil }, set: { if !$0 { errorPerfil = nil } })) {
            Button("OK") { errorPerfil = nil }
        } message: {
            Text(errorPerfil ?? "")
        }
    }

    // MARK: Enlaces

    private var perfilBinding: Binding<String> {
        Binding(
            get: { modelo.perfilElegido },
            set: { nombre in
                if let p = modelo.perfiles.first(where: { $0.nombre == nombre }) {
                    modelo.aplicar(p)
                } else {
                    modelo.perfilElegido = ""
                }
            })
    }

    private func origen(_ o: Opciones.Origen) -> Binding<Bool> {
        Binding(
            get: { modelo.opciones.origenes.contains(o) },
            set: { activo in
                if activo { modelo.opciones.origenes.insert(o) } else { modelo.opciones.origenes.remove(o) }
            })
    }

    private var textoEsteIPhone: String {
        if let m = modelo.modeloEsteIPhone { return tr("Solo de este iPhone (%@)", m) }
        return tr("Solo de este iPhone (se deduce de sus fotos recientes)")
    }

    /// Ejecuta una acción de perfil y muestra su confirmación (o el error).
    private func hacer(_ accion: () throws -> String) {
        do {
            let m = try accion()
            if !m.isEmpty { avisoPerfil = m }
        } catch {
            errorPerfil = error.localizedDescription
        }
    }

    private func camara(_ m: String) -> Binding<Bool> {
        Binding(
            get: { modelo.opciones.camaras?.contains(m) ?? false },
            set: { activa in
                var lista = modelo.opciones.camaras ?? []
                if activa { if !lista.contains(m) { lista.append(m) } } else { lista.removeAll { $0 == m } }
                modelo.opciones.camaras = lista
            })
    }

    private func etiquetaCamara(_ m: String) -> String {
        guard let c = modelo.camarasDetectadas.first(where: { $0.modelo == m }) else { return m }
        return tr("%@  (%ld fotos, %ld vídeos)", c.etiqueta, c.fotos, c.videos)
    }

    private func aplicarVideoMax() {
        if textoVideoMax.trimmingCharacters(in: .whitespaces).isEmpty {
            modelo.opciones.videoMaximo = nil
        } else if let b = Opciones.bytes(textoVideoMax) {
            modelo.opciones.videoMaximo = b
        }
    }

    private func elegirCarpeta() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("Elegir")
        panel.directoryURL = modelo.destinoURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            modelo.destinoTexto = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
