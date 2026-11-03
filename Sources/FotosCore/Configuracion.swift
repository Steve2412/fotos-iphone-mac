import Foundation

public enum ErrorHerramienta: LocalizedError {
    case argumentos(String)
    case sinIPhone
    case sinRespuesta
    case accesoDenegado
    case sesion(String)
    case lista(String)
    case copia(String)
    case cancelado

    public var errorDescription: String? {
        switch self {
        case .argumentos(let m): return m
        case .sinIPhone:
            return tr("No se encontró ningún iPhone por USB. Conéctalo, desbloquéalo y acepta «Confiar en este ordenador».")
        case .sinRespuesta:
            return tr("El iPhone no abrió la sesión. Desbloquéalo, acepta «Confiar en este ordenador», cierra Fotos y deja Captura de Imagen abierta en el Mac.")
        case .accesoDenegado:
            return tr("macOS no deja a Terminal leer el contenido del iPhone. Permítelo en Ajustes del Sistema → Privacidad y seguridad y vuelve a intentarlo.")
        case .sesion(let m):
            return tr("No se pudo abrir la sesión con el iPhone: %@\n   Prueba a desconectar el cable y volver a conectarlo con el iPhone ya desbloqueado.\n   Si sigue igual, abre Captura de Imagen en el Mac: si ahí tampoco se ven las fotos,\n   el iPhone no confía en este Mac (se arregla en el iPhone con Ajustes → General →\n   Transferir o restablecer → Restablecer → Restablecer localización y privacidad).", m)
        case .lista(let m): return m
        case .copia(let m): return m
        case .cancelado: return tr("Cancelado. No se ha copiado nada.")
        }
    }
}

/// Parámetros de una ejecución: qué hacer y dónde. Qué se copia está en `opciones`.
/// La lectura de los argumentos de Terminal está en el módulo de la herramienta.
public struct Configuracion {
    public enum Modo {
        case inspeccionar, volcar, transferir, camaras
        /// Preguntas paso a paso (sin argumentos, o con --asistente).
        case asistente
        /// Mostrar los perfiles (no necesita el iPhone).
        case perfiles
        /// Solo guardar un perfil (no necesita el iPhone).
        case guardarPerfil
    }

    public var modo: Modo = .transferir
    /// Lista del álbum generada por el Atajo (alternativa al periodo).
    public var lista: URL?
    public var destino: URL?
    public var simular = false
    public var borrar = false
    public var numeros: [Int] = []
    /// Con --inspeccionar: elementos de otras apps por nombre (THQV8599).
    public var nombres: [String] = []
    public var ultimos = 30
    /// Código de idioma pedido con --idioma (nil = el del sistema).
    public var idioma: String?
    public var opciones = Opciones()
    /// Perfil cargado con --perfil (sus opciones ya están en `opciones`).
    public var perfil: String?
    /// Nombre con el que guardar las opciones (--guardar-perfil).
    public var guardarPerfil: String?
    /// Antes de una copia real: simular, mostrar el resumen y pedir confirmación (--si lo salta).
    public var confirmar = true
    /// Mostrar cada archivo (en las simulaciones previas a confirmar solo se muestra el resumen).
    public var detalle = true
    /// Mostrar el resumen de opciones al empezar.
    public var mostrarOpciones = true

    public init() {}

    /// Los elementos se eligen por el periodo de `opciones` (y no con la lista del Atajo).
    public var porFechas: Bool { lista == nil || opciones.periodo != .todo }

    public static func dia(_ texto: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: texto)
    }
}
