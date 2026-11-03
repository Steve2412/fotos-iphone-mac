import SwiftUI
import AppKit
import FotosCore

/// La copia en curso (progreso, velocidad, tiempo restante, pausa y cancelación) y,
/// al terminar, su resumen.
struct PanelCopia: View {
    @Environment(ModeloApp.self) private var modelo
    @State private var verErrores = false

    var body: some View {
        let p = modelo.progreso
        VStack(alignment: .leading, spacing: 14) {
            cabecera

            ProgressView(value: p.fraccion)
                .controlSize(.large)

            HStack(spacing: 18) {
                Text(tr("%@ de %@", formatoBytes(p.bytesActuales), formatoBytes(p.bytesTotal)))
                Text(tr("elemento %ld de %ld", min(p.elementosHechos + (modelo.copiando ? 1 : 0), p.elementosTotal), p.elementosTotal))
                if modelo.copiando {
                    if modelo.pausada {
                        Text(tr("en pausa")).foregroundStyle(.orange)
                    } else if let v = p.velocidad {
                        Text(tr("%@/s", formatoBytes(Int64(v))))
                        if let r = p.restante {
                            Text(tr("quedan unos %@", formatoDuracion(r)))
                        }
                    } else {
                        Text(tr("midiendo la velocidad…")).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout.monospacedDigit())

            if modelo.copiando, let nombre = p.archivoActual {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                    Text(nombre).font(.callout.monospaced())
                    ProgressView(value: p.fraccionActual)
                        .frame(width: 140)
                        .controlSize(.small)
                    Text(formatoBytes(p.tamanoActual)).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Dato(valor: p.copiados, nombre: tr("copiados"), color: .green)
                Dato(valor: p.yaExistian, nombre: tr("ya existían"), color: .blue)
                if p.movidos > 0 { Dato(valor: p.movidos, nombre: tr("movidos"), color: .teal) }
                Dato(valor: p.descartados, nombre: tr("descartados"), color: .secondary)
                if !p.errores.isEmpty { Dato(valor: p.errores.count, nombre: tr("avisos y errores"), color: .red) }
            }

            if !p.errores.isEmpty {
                DisclosureGroup(isExpanded: $verErrores) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(p.errores.suffix(200).enumerated()), id: \.offset) { _, e in
                            Text(e).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text(tr("Ver avisos y errores (%ld)", p.errores.count)).font(.callout)
                }
            }

            nota
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 28)
    }

    // MARK: Partes

    private var cabecera: some View {
        HStack(spacing: 10) {
            Image(systemName: icono).font(.title2).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.headline)
                if let d = modelo.destinoCopia {
                    Text(d.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if modelo.copiando {
                Button(modelo.pausada ? tr("Reanudar") : tr("Pausar")) {
                    modelo.pausar(!modelo.pausada)
                }
                .disabled(modelo.cancelando)
                Button(tr("Cancelar")) { modelo.cancelarCopia() }
                    .disabled(modelo.cancelando)
            } else {
                if let d = modelo.destinoCopia {
                    Button(tr("Abrir carpeta")) { NSWorkspace.shared.open(d) }
                }
                if let i = modelo.informeCopia {
                    Button(tr("Ver informe")) { NSWorkspace.shared.activateFileViewerSelecting([i]) }
                }
                Button(tr("Listo")) { modelo.cerrarCopia() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var nota: some View {
        switch modelo.estadoCopia {
        case .copiando:
            if modelo.cancelando {
                Text(tr("Cancelando: se detiene al terminar el archivo en curso."))
                    .font(.callout).foregroundStyle(.orange)
            } else {
                Text(tr("Pausar y cancelar se aplican al terminar el archivo en curso. Lo ya copiado se queda en el destino y, la próxima vez, se salta. No se borra nada del iPhone."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .terminada:
            Text(tr("Pulsa Simular otra vez si quieres comprobar que todo está en el destino."))
                .font(.callout).foregroundStyle(.secondary)
        case .cancelada:
            Text(tr("Lo ya copiado se queda en el destino. Simula y copia otra vez para seguir: se salta lo que ya está."))
                .font(.callout).foregroundStyle(.secondary)
        case .error(let m):
            Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .nada:
            EmptyView()
        }
    }

    private var titulo: String {
        switch modelo.estadoCopia {
        case .copiando:
            if modelo.cancelando { return tr("Cancelando…") }
            return modelo.pausada ? tr("Copia en pausa") : tr("Copiando…")
        case .terminada:
            return modelo.progreso.errores.isEmpty ? tr("Copia terminada") : tr("Copia terminada con avisos")
        case .cancelada: return tr("Copia cancelada")
        case .error: return tr("La copia se interrumpió")
        case .nada: return ""
        }
    }

    private var icono: String {
        switch modelo.estadoCopia {
        case .copiando: return modelo.pausada ? "pause.circle.fill" : "arrow.down.circle.fill"
        case .terminada: return modelo.progreso.errores.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        case .cancelada: return "stop.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .nada: return "circle"
        }
    }

    private var color: Color {
        switch modelo.estadoCopia {
        case .copiando: return modelo.pausada ? .orange : .accentColor
        case .terminada: return modelo.progreso.errores.isEmpty ? .green : .orange
        case .cancelada: return .orange
        case .error: return .red
        case .nada: return .secondary
        }
    }
}

private struct Dato: View {
    let valor: Int
    let nombre: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(valor)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
            Text(nombre).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 90, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
