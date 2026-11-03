import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FotosCore
import FotosIPhoneKit

/// Borrar del iPhone lo que ya está completo en un respaldo: se elige el respaldo (la carpeta
/// de destino o el informe.csv de una copia), se revisa qué se borraría y, para borrar,
/// hay que escribir una clave («BORRAR 12»).
struct PanelBorrado: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var pidiendoClave = false

    var body: some View {
        @Bindable var modelo = modelo
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Borrar del iPhone lo que ya está en el respaldo")).font(.title3.weight(.semibold))
            Text(tr("Solo se borran los elementos cuyo original (y su versión editada, si la tiene) están en el respaldo con el mismo tamaño que en el iPhone. Lo que falte o esté a medias no se toca."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            origen

            HStack(spacing: 12) {
                Button {
                    Task { await modelo.revisarBorrado() }
                } label: {
                    Label(modelo.planBorrado == nil ? tr("Revisar qué se borraría") : tr("Revisar otra vez"),
                          systemImage: "magnifyingglass")
                }
                .controlSize(.large)
                .disabled(modelo.motivoNoRevisar != nil || modelo.ocupado)

                if let plan = modelo.planBorrado, !modelo.borrando {
                    Button(role: .destructive) {
                        pidiendoClave = true
                    } label: {
                        Label(tr("Borrar %ld elementos del iPhone…", plan.aBorrar.count), systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(modelo.motivoNoBorrar != nil)
                    .help(modelo.motivoNoBorrar ?? "")
                }
                if modelo.estadoBorrado == .revisando {
                    ProgressView().controlSize(.small)
                    Text(tr("Comprobando el respaldo…")).foregroundStyle(.secondary)
                }
            }

            estado

            if modelo.borrando || modelo.estadoBorrado == .terminado {
                ProgresoBorrado()
            } else if let plan = modelo.planBorrado {
                VistaPlan(plan: plan)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .sheet(isPresented: $pidiendoClave) {
            ConfirmarBorrado()
        }
    }

    // MARK: Origen

    private var origen: some View {
        @Bindable var modelo = modelo
        return VStack(alignment: .leading, spacing: 8) {
            Picker(tr("Qué borrar"), selection: $modelo.origenBorrado) {
                Text(tr("Lo del periodo elegido que esté en la carpeta de destino"))
                    .tag(ModeloApp.OrigenBorrado.carpeta)
                Text(tr("Lo que copió una copia anterior (su informe.csv)"))
                    .tag(ModeloApp.OrigenBorrado.informe)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(modelo.ocupado)

            Group {
                switch modelo.origenBorrado {
                case .carpeta:
                    Text(tr("Respaldo: %@", modelo.destinoURL.path))
                    Text(tr("Periodo: %@ · Organización: %@", modelo.opciones.periodo.descripcion,
                            modelo.opciones.organizacion.texto))
                    Text(tr("Se cambian en el panel de la izquierda."))
                        .foregroundStyle(.tertiary)
                case .informe:
                    HStack {
                        Text(modelo.informeParaBorrar?.path ?? tr("Ningún informe elegido"))
                            .lineLimit(1).truncationMode(.middle)
                        Button(tr("Elegir informe…")) { elegirInforme() }
                            .disabled(modelo.ocupado)
                    }
                    if let c = modelo.carpetaRespaldo {
                        Text(tr("Respaldo: %@ (la carpeta del informe)", c.path))
                    }
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var estado: some View {
        if let m = modelo.motivoNoRevisar {
            Text(m).font(.callout).foregroundStyle(.secondary)
        } else if case .error(let m) = modelo.estadoBorrado {
            Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        } else if modelo.planDesactualizado {
            Label(tr("Has cambiado la carpeta, el informe o el periodo: revisa otra vez."),
                  systemImage: "arrow.clockwise.circle")
                .foregroundStyle(.orange)
        }
    }

    private func elegirInforme() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = tr("Elegir")
        panel.message = tr("Elige el informe.csv que dejó una copia en su carpeta de destino.")
        panel.directoryURL = modelo.carpetaRespaldo ?? modelo.destinoURL
        if panel.runModal() == .OK, let url = panel.url {
            modelo.informeParaBorrar = url
        }
    }
}

// MARK: Plan

/// Qué se borraría, qué no se toca y por qué.
private struct VistaPlan: View {
    let plan: PlanBorrado
    @State private var verIncompletos = false
    @State private var verSinCopia = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Cuenta(valor: plan.aBorrar.count, nombre: tr("se borrarían"),
                       detalle: tr("%ld archivos · %@", plan.archivos.count, formatoBytes(plan.bytes)), color: .red)
                Cuenta(valor: plan.noRespaldados.count, nombre: tr("no están en el respaldo"),
                       detalle: tr("no se tocan"), color: .secondary)
                Cuenta(valor: plan.incompletos.count, nombre: tr("respaldo incompleto"),
                       detalle: tr("no se tocan"), color: plan.incompletos.isEmpty ? .secondary : .orange)
            }

            if !plan.sinCopia.isEmpty {
                DisclosureGroup(isExpanded: $verSinCopia) {
                    nombres(plan.sinCopia.map(\.nombre))
                } label: {
                    Label(tr("%ld archivos se borrarían con su elemento sin estar en el respaldo (vídeos de Live Photos, .AAE…). Si los quieres conservar, cópialos antes.", plan.sinCopia.count),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !plan.incompletos.isEmpty {
                DisclosureGroup(isExpanded: $verIncompletos) {
                    nombres(plan.incompletos.map { "\($0.elemento.etiqueta): " + tr("falta %@", $0.faltan.joined(separator: ", ")) })
                } label: {
                    Text(tr("Ver los %ld elementos con respaldo incompleto", plan.incompletos.count))
                }
            }

            if !plan.aBorrar.isEmpty {
                AvisoDefinitivo()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 130), spacing: 10)], spacing: 12) {
                    ForEach(plan.aBorrar, id: \.etiquetaUnica) { el in
                        CeldaBorrado(elemento: el)
                    }
                }
            } else {
                Text(tr("Nada que borrar: ningún elemento tiene su respaldo completo en esa carpeta."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func nombres(_ lista: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lista.prefix(300).enumerated()), id: \.offset) { _, n in
                Text(n).font(.caption.monospaced()).textSelection(.enabled)
            }
            if lista.count > 300 { Text("…").font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Elemento {
    /// Para identificar la celda (dos IMG_0001 de distinta fecha son elementos distintos).
    var etiquetaUnica: ObjectIdentifier { ObjectIdentifier(self) }
}

private struct Cuenta: View {
    let valor: Int
    let nombre: String
    let detalle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(valor)").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(nombre).font(.callout.weight(.medium))
            Text(detalle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 140, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// El borrado por cable no tiene vuelta atrás.
private struct AvisoDefinitivo: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red).font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("El borrado es definitivo")).font(.headline)
                Text(tr("Por cable no pasa por «Eliminados recientemente». Si usas Fotos de iCloud, también se borran de iCloud y de tus otros dispositivos."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CeldaBorrado: View {
    @Environment(ModeloApp.self) private var modelo
    let elemento: Elemento
    @State private var imagen: CGImage?

    private var principal: Archivo? { elemento.imagenOriginal ?? elemento.videoOriginal }

    var body: some View {
        VStack(spacing: 3) {
            Color.clear
                .frame(width: 104, height: 104)
                .overlay {
                    if let imagen {
                        Image(decorative: imagen, scale: 1).resizable().scaledToFill()
                    } else {
                        Image(systemName: elemento.imagenOriginal == nil ? "video" : "photo")
                            .font(.title2).foregroundStyle(.tertiary)
                    }
                }
                .background(.quaternary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(elemento.etiqueta).font(.caption).lineLimit(1)
            if let f = elemento.fecha {
                Text(f, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help(elemento.archivos.map(\.nombre).joined(separator: ", "))
        .task {
            guard imagen == nil, let a = principal else { return }
            imagen = await modelo.miniaturas.imagen(de: a)
        }
    }
}

// MARK: Confirmación

/// Hay que escribir la clave exacta («BORRAR 12»): un clic por error no borra nada.
private struct ConfirmarBorrado: View {
    @Environment(ModeloApp.self) private var modelo
    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""

    private var clave: String { tr("BORRAR %ld", modelo.planBorrado?.aBorrar.count ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("Borrar del iPhone"), systemImage: "trash").font(.title2.weight(.semibold))
            if let plan = modelo.planBorrado {
                Text(tr("Se borrarán del iPhone %ld elementos (%ld archivos, %@). Su respaldo está completo en %@.",
                        plan.aBorrar.count, plan.archivos.count, formatoBytes(plan.bytes),
                        modelo.carpetaRespaldo?.path ?? ""))
                    .fixedSize(horizontal: false, vertical: true)
            }
            AvisoDefinitivo()
            Text(tr("Para continuar escribe exactamente «%@»:", clave))
            TextField(clave, text: $texto)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit { confirmar() }
            HStack {
                Spacer()
                Button(tr("Cancelar"), role: .cancel) { cerrar() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Borrar"), role: .destructive) { confirmar() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(texto != clave)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    private func confirmar() {
        guard texto == clave else { return }
        cerrar()
        Task { await modelo.borrar() }
    }
}

// MARK: Progreso y resultado

private struct ProgresoBorrado: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var verFallos = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: modelo.borrando ? "trash.circle.fill" : icono)
                    .font(.title2).foregroundStyle(modelo.borrando ? .red : color)
                Text(titulo).font(.headline)
                Spacer()
                if modelo.borrando {
                    Button(tr("Detener")) { modelo.detenerBorrado() }
                } else {
                    if let r = modelo.resultadoBorrado {
                        Button(tr("Ver informe")) { NSWorkspace.shared.activateFileViewerSelecting([r.informe]) }
                    }
                    Button(tr("Volver a leer el iPhone")) {
                        Task { await modelo.cerrarBorradoYReconectar() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            ProgressView(value: Double(modelo.borradoHechos), total: Double(max(modelo.borradoTotal, 1)))
            HStack(spacing: 16) {
                Text(tr("%ld de %ld elementos", modelo.borradoHechos, modelo.borradoTotal))
                if modelo.borrando, let e = modelo.borradoActual {
                    Text(tr("último: %@", e)).foregroundStyle(.secondary)
                }
            }
            .font(.callout.monospacedDigit())
            if let r = modelo.resultadoBorrado {
                Text(tr("Archivos borrados (comprobado en el iPhone): %ld · no borrados: %ld", r.borrados, r.fallidos))
                if modelo.borradoDetenido {
                    Text(tr("Se detuvo antes de terminar: el resto no se ha tocado.")).foregroundStyle(.orange)
                }
                Text(tr("El iPhone ha cambiado: pulsa «Volver a leer el iPhone» antes de copiar o borrar otra vez."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if modelo.borrando {
                Text(tr("Detener se aplica al terminar el elemento en curso. Cada borrado se comprueba en el iPhone."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !modelo.borradoFallos.isEmpty {
                DisclosureGroup(isExpanded: $verFallos) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(modelo.borradoFallos.enumerated()), id: \.offset) { _, f in
                            Text(f).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(tr("Siguen en el iPhone (%ld)", modelo.borradoFallos.count)).foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var titulo: String {
        if modelo.borrando { return tr("Borrando del iPhone…") }
        if modelo.borradoDetenido { return tr("Borrado detenido") }
        return (modelo.resultadoBorrado?.fallidos ?? 0) == 0 ? tr("Borrado terminado") : tr("Borrado terminado con fallos")
    }

    private var icono: String {
        (modelo.resultadoBorrado?.fallidos ?? 0) == 0 && !modelo.borradoDetenido
            ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var color: Color {
        (modelo.resultadoBorrado?.fallidos ?? 0) == 0 && !modelo.borradoDetenido ? .green : .orange
    }
}
