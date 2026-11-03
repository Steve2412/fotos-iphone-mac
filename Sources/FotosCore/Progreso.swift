import Foundation

/// Velocidad de copia a partir de muestras (instante, bytes copiados hasta entonces),
/// usando solo las de los últimos segundos para que reaccione a los cambios.
public struct MedidorVelocidad {
    public let ventana: TimeInterval
    private var muestras: [(fecha: Date, bytes: Int64)] = []

    public init(ventana: TimeInterval = 8) {
        self.ventana = ventana
    }

    public mutating func anotar(_ bytes: Int64, en fecha: Date = Date()) {
        muestras.append((fecha, bytes))
        // Se guarda una muestra anterior a la ventana para medir desde su borde.
        while muestras.count > 2, fecha.timeIntervalSince(muestras[1].fecha) > ventana {
            muestras.removeFirst()
        }
    }

    /// Tras una pausa: lo anterior no cuenta para la velocidad.
    public mutating func reiniciar() {
        muestras.removeAll()
    }

    /// Bytes por segundo (nil hasta tener al menos un segundo de muestras).
    public var bytesPorSegundo: Double? {
        guard let primera = muestras.first, let ultima = muestras.last else { return nil }
        let t = ultima.fecha.timeIntervalSince(primera.fecha)
        guard t >= 1 else { return nil }
        return Double(max(ultima.bytes - primera.bytes, 0)) / t
    }

    /// Segundos que faltan para copiar `faltan` bytes a la velocidad actual.
    public func restante(_ faltan: Int64) -> TimeInterval? {
        guard let v = bytesPorSegundo, v > 0 else { return nil }
        return Double(max(faltan, 0)) / v
    }
}

/// «45 s», «3 min», «1 h 05 min».
public func formatoDuracion(_ segundos: TimeInterval) -> String {
    let s = Int(segundos.rounded())
    if s < 60 { return tr("%ld s", max(s, 1)) }
    let minutos = Int((segundos / 60).rounded())
    if minutos < 60 { return tr("%ld min", minutos) }
    return tr("%ld h %@ min", minutos / 60, String(format: "%02d", minutos % 60))
}
