import SwiftUI
import AppKit
import FotosCore
import FotosIPhoneKit

/// Botón Simular, su progreso y la vista previa: qué se copiaría, qué ya está copiado
/// y qué se descarta (y por qué), con miniaturas pedidas al iPhone.
struct PanelSimulacion: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var categoria: ElementoSimulado.Categoria = .seCopiara
    /// Con «Descartados»: solo los de este motivo (nil = todos).
    @State private var motivo: String?
    @State private var confirmandoCopia = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            barra
            estado
            if let vista = modelo.vistaPrevia, !modelo.simulando {
                resultados(vista)
            }
        }
        .padding(.horizontal, 28)
        .alert(tr("¿Copiar ahora?"), isPresented: $confirmandoCopia) {
            Button(tr("Copiar")) { Task { await modelo.copiar() } }
            Button(tr("Cancelar"), role: .cancel) {}
        } message: {
            Text(textoConfirmacion)
        }
        .onChange(of: modelo.numeroSimulacion) {
            // Tras cada simulación se enseña primero lo que se copiaría (o lo que haya).
            guard let v = modelo.vistaPrevia else { return }
            categoria = ElementoSimulado.Categoria.allCases.first { !v.elementos($0).isEmpty } ?? .seCopiara
            motivo = nil
        }
    }

    // MARK: Barra

    private var barra: some View {
        HStack(spacing: 12) {
            Button {
                Task { await modelo.simular() }
            } label: {
                Label(modelo.vistaPrevia == nil ? tr("Simular") : tr("Volver a simular"), systemImage: "eye")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!modelo.puedeSimular)

            if modelo.vistaPrevia != nil && !modelo.simulando {
                Button {
                    confirmandoCopia = true
                } label: {
                    Label(tr("Copiar…"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!modelo.puedeCopiar)
                .help(modelo.motivoNoCopiar ?? tr("Copia al Mac lo que muestra la simulación."))
            }

            if modelo.simulando {
                ProgressView(value: Double(modelo.simHechos), total: Double(max(modelo.simTotal, 1)))
                    .frame(width: 220)
                Text(tr("%ld de %ld", modelo.simHechos, modelo.simTotal))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(tr("Cancelar")) { modelo.cancelarSimulacion() }
            }
            Spacer()
            if let url = modelo.informeSimulacion, !modelo.simulando {
                Button(tr("Ver informe")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .help(url.path)
            }
        }
    }

    private var textoConfirmacion: String {
        guard let v = modelo.vistaPrevia else { return "" }
        var partes: [String] = []
        if v.archivosACopiar > 0 {
            partes.append(tr("Se copiarán %ld archivos (%@) a %@.", v.archivosACopiar, formatoBytes(v.bytesACopiar), modelo.destinoURL.path))
        }
        if v.archivosAMover > 0 {
            partes.append(tr("%ld archivos ya copiados se moverán a la carpeta que les toca.", v.archivosAMover))
        }
        partes.append(tr("Lo ya copiado no se repite y no se borra nada del iPhone."))
        if modelo.faltaEspacio, let libre = modelo.espacioLibre {
            partes.append(tr("⚠️ Solo quedan %@ libres en el destino: puede que no quepa todo.", formatoBytes(libre)))
        }
        return partes.joined(separator: "\n\n")
    }

    @ViewBuilder
    private var estado: some View {
        if let m = modelo.motivoNoSimular {
            Text(m).font(.callout).foregroundStyle(.secondary)
        } else if modelo.simulando {
            Text(tr("Simulando: se lee la cámara de cada foto (la primera vez tarda; después lo recuerda). No se copia nada."))
                .font(.callout).foregroundStyle(.secondary)
        } else {
            switch modelo.estadoSimulacion {
            case .error(let m):
                Label(m, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .cancelada:
                Label(tr("Simulación cancelada: se muestra lo revisado hasta entonces."), systemImage: "stop.circle")
                    .foregroundStyle(.orange)
            case .nada:
                Text(tr("Simular no copia ni borra nada: dice qué se copiaría con estas opciones."))
                    .font(.callout).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
            if modelo.vistaPrevia != nil && modelo.faltaEspacio, let libre = modelo.espacioLibre {
                Label(tr("Solo quedan %@ libres en el destino y la copia ocupa %@.", formatoBytes(libre),
                         formatoBytes(modelo.vistaPrevia?.bytesACopiar ?? 0)),
                      systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            if modelo.simulacionDesactualizada {
                Label(tr("Has cambiado las opciones o el destino: vuelve a simular para ver el resultado."),
                      systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Resultados

    @ViewBuilder
    private func resultados(_ v: ModeloApp.VistaPrevia) -> some View {
        HStack(spacing: 12) {
            ForEach(ElementoSimulado.Categoria.allCases) { c in
                let n = v.elementos(c).count
                if c != .conError || n > 0 {
                    Button {
                        categoria = c
                        motivo = nil
                    } label: {
                        Contador(valor: n, nombre: c.texto, detalle: detalle(c, v),
                                 color: color(c), elegido: categoria == c)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if v.archivosAMover > 0 {
            Text(tr("%ld archivos ya copiados se moverían a la carpeta que les toca con esta organización (sin volver a descargarlos).", v.archivosAMover))
                .font(.callout).foregroundStyle(.secondary)
        }
        if modelo.vistaPrevia != nil && !FileManager.default.fileExists(atPath: modelo.destinoURL.path) {
            Text(tr("La carpeta de destino aún no existe: todo lo elegido se copiaría."))
                .font(.callout).foregroundStyle(.secondary)
        }

        if categoria == .descartado && !v.motivos.isEmpty {
            Motivos(motivos: v.motivos, total: v.elementos(.descartado).count, elegido: $motivo)
        }

        let lista = v.elementos(categoria).filter { motivo == nil || $0.motivo == motivo }
        if lista.isEmpty {
            Text(tr("No hay nada en este grupo."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 12)], spacing: 14) {
                ForEach(lista) { el in
                    CeldaElemento(elemento: el)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func detalle(_ c: ElementoSimulado.Categoria, _ v: ModeloApp.VistaPrevia) -> String {
        switch c {
        case .seCopiara: return tr("%ld archivos · %@", v.archivosACopiar, formatoBytes(v.bytesACopiar))
        case .yaCopiado: return tr("en el destino")
        case .descartado: return tr("%ld motivos", v.motivos.count)
        case .conError: return tr("ver detalle")
        }
    }

    private func color(_ c: ElementoSimulado.Categoria) -> Color {
        switch c {
        case .seCopiara: return .green
        case .yaCopiado: return .blue
        case .descartado: return .secondary
        case .conError: return .red
        }
    }
}

/// Un contador que también sirve para elegir el grupo que se ve.
private struct Contador: View {
    let valor: Int
    let nombre: String
    let detalle: String
    let color: Color
    let elegido: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(valor)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(nombre).font(.callout.weight(.medium))
            Text(detalle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 130, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(elegido ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(elegido ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Motivos de descarte, de más a menos frecuente; al pulsar uno se filtra la cuadrícula.
private struct Motivos: View {
    let motivos: [(motivo: String, elementos: Int)]
    let total: Int
    @Binding var elegido: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Por qué se descartan")).font(.headline)
            fila(texto: tr("Todos"), n: total, activo: elegido == nil) { elegido = nil }
            ForEach(motivos.indices, id: \.self) { i in
                let m = motivos[i]
                fila(texto: m.motivo.isEmpty ? tr("(sin motivo)") : m.motivo, n: m.elementos,
                     activo: elegido == m.motivo) { elegido = m.motivo }
            }
        }
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func fila(texto: String, n: Int, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack {
                Image(systemName: activo ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(activo ? Color.accentColor : .secondary)
                Text(texto).lineLimit(2)
                Spacer()
                Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Miniatura de un elemento con su nombre y fecha; al pulsarla, el detalle de sus archivos.
private struct CeldaElemento: View {
    @Environment(ModeloApp.self) private var modelo
    let elemento: ElementoSimulado
    @State private var imagen: CGImage?
    @State private var verDetalle = false

    var body: some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(width: 112, height: 112)
                .overlay {
                    if let imagen {
                        Image(decorative: imagen, scale: 1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: elemento.esVideo ? "video" : "photo")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .background(.quaternary.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) { insignia }
                .opacity(elemento.categoria == .descartado ? 0.5 : 1)
            Text(elemento.etiqueta)
                .font(.caption)
                .lineLimit(1)
            if let fecha = elemento.fecha {
                Text(fecha, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { verDetalle = true }
        .help(elemento.motivo ?? elemento.etiqueta)
        .popover(isPresented: $verDetalle, arrowEdge: .bottom) {
            DetalleElemento(elemento: elemento, imagen: imagen)
        }
        .task(id: elemento.id) {
            guard imagen == nil, let a = elemento.principal else { return }
            imagen = await modelo.miniaturas.imagen(de: a)
        }
    }

    @ViewBuilder
    private var insignia: some View {
        if elemento.esVideo || elemento.esLivePhoto {
            Image(systemName: elemento.esVideo ? "video.fill" : "livephoto")
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(5)
        }
    }
}

/// Qué pasaría con cada archivo del elemento.
private struct DetalleElemento: View {
    let elemento: ElementoSimulado
    let imagen: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let imagen {
                    Image(decorative: imagen, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 160, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(elemento.etiqueta).font(.headline)
                    if let fecha = elemento.fecha {
                        Text(formatoFecha(fecha)).foregroundStyle(.secondary)
                    }
                    Text(elemento.categoria.texto).foregroundStyle(.secondary)
                }
            }
            Divider()
            ForEach(Array(elemento.archivos.enumerated()), id: \.offset) { _, a in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(a.resultado.icono).frame(width: 16)
                        Text(a.archivo.nombre).font(.body.monospaced())
                        Spacer()
                        Text(formatoBytes(a.archivo.tamano)).foregroundStyle(.secondary)
                    }
                    Text("\(a.tipo.texto) · \(a.resultado.texto)" + (a.motivo.isEmpty ? "" : " — \(a.motivo)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 22)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}
