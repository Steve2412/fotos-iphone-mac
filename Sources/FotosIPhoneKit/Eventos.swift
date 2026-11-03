import Foundation
import FotosCore

/// Estado de la conexión con el iPhone.
public enum EstadoConexion: Equatable {
    case buscando
    case encontrado(nombre: String)
    /// El iPhone rechaza la sesión (bloqueado o sin confiar todavía en el Mac): se reintenta.
    case esperando(intentos: Int, mensaje: String)
    case sesionAbierta
    case bloqueado
    case desbloqueado
    case catalogo(porcentaje: Int)
    case listo
    /// Se desconectó con la sesión ya abierta.
    case desconectado
}

/// Lo que va pasando en la biblioteca. La Terminal imprime los `.mensaje`; la app usa el resto
/// para su interfaz (barras de progreso, contadores…). Siempre se emiten en el hilo principal.
public enum Evento {
    /// Texto ya traducido, tal como lo muestra la Terminal.
    case mensaje(String)
    case conexion(EstadoConexion)
    /// Empieza una copia o simulación con estos elementos.
    case inicio(elementos: Int, simulacion: Bool)
    case elemento(indice: Int, total: Int, etiqueta: String)
    /// Qué pasó con un archivo (copiado, descartado…).
    case archivo(etiqueta: String, archivo: Archivo, tipo: TipoArchivo, resultado: Resultado, motivo: String)
    /// Avance de la descarga de un archivo (0…1).
    case descarga(nombre: String, fraccion: Double, tamano: Int64)
    /// Copia en pausa o reanudada.
    case pausa(Bool)
    case cancelada
    case fin(informe: URL)
    /// Borrado de un elemento terminado; `pendientes`: archivos que siguen en el iPhone.
    case borrando(indice: Int, total: Int, etiqueta: String, pendientes: [String])
}

public typealias Observador = (Evento) -> Void

public enum Observadores {
    /// El de la Terminal: imprime los mensajes y nada más.
    public static let terminal: Observador = { evento in
        if case .mensaje(let texto) = evento { print(texto) }
    }
}

/// Pausa y cancelación de una copia desde fuera (la app). Se consulta entre archivos.
public final class ControlCopia: @unchecked Sendable {
    public var pausado = false
    public private(set) var cancelado = false

    public init() {}

    public func cancelar() {
        cancelado = true
        pausado = false
    }

    /// Espera mientras esté en pausa. Devuelve false si se canceló.
    @MainActor
    func continuar() async -> Bool {
        while pausado && !cancelado {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !cancelado
    }
}
