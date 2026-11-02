import Foundation
import FotosCore

/// Lectura de los argumentos de Terminal. Cada opción se acepta en español y en inglés.
extension Configuracion {

    /// Opciones en inglés → su nombre en español.
    private static let alias: [String: String] = [
        "--from": "--desde", "--to": "--hasta", "--list": "--lista",
        "--dest": "--destino", "--destination": "--destino",
        "--simulate": "--simular", "--dry-run": "--simular",
        "--model": "--modelo", "--delete": "--borrar",
        "--inspect": "--inspeccionar", "--dump": "--volcar",
        "--last": "--ultimos", "--number": "--numero", "--name": "--nombre",
        "--help": "--ayuda", "-h": "--ayuda", "--language": "--idioma",
    ]

    /// Busca --idioma / --language antes de leer lo demás, para que los errores salgan ya traducidos.
    static func idiomaPedido(en argumentos: [String]) -> String? {
        for (i, a) in argumentos.enumerated() where a == "--idioma" || a == "--language" {
            if i + 1 < argumentos.count { return argumentos[i + 1] }
        }
        return nil
    }

    /// La ayuda va con una clave propia («AYUDA») porque es un texto largo;
    /// en.lproj tiene la versión en inglés, con las opciones en inglés.
    static var ayuda: String { Idioma.texto("AYUDA", porDefecto: ayudaEspanol) }

    static let ayudaEspanol = """
    fotos-iphone — copia las fotos y vídeos del iPhone al Mac por USB, con los archivos originales.

    USO
      fotos-iphone --desde 2026-01-01 --hasta 2026-01-31 --destino ~/Pictures/MiRespaldo [--simular]
      fotos-iphone --lista album.txt --destino ~/Pictures/Viaje [--simular]
      fotos-iphone --inspeccionar [--ultimos 30 | --numero 1234 --numero 1235 | --nombre THQV8599]

    OPCIONES
      --desde AAAA-MM-DD Copia lo hecho desde ese día (incluido).
      --hasta AAAA-MM-DD …hasta ese día (incluido). Se usa en lugar de --lista.
      --lista RUTA       Lista del álbum generada por el Atajo
                         (una línea por elemento: IMG_1234|2026-10-20T14:33:12).
      --destino RUTA     Carpeta donde se guardan los archivos y el informe.csv.
      --simular          Muestra qué se copiaría y qué se descartaría, sin copiar nada.
      --modelo NOMBRE    Modelo de cámara aceptado (por defecto "iPhone 17 Pro"). Se puede repetir.
      --borrar           Borra del iPhone lo ya respaldado en --destino (pide confirmación;
                         con --simular solo muestra qué borraría). EXPERIMENTAL.
      --sha256           Añade al informe la huella SHA-256 de cada archivo copiado.
      --inspeccionar     Muestra cómo ve el Mac los archivos del iPhone (nombres, grupos, origen, cámara).
      --volcar           Guarda en catalogo-iphone.csv todos los archivos que muestra el iPhone (diagnóstico).
      --ultimos N        Con --inspeccionar: los N elementos más recientes (30 por defecto).
      --numero N         Con --inspeccionar: solo el elemento IMG_N. Se puede repetir.
      --nombre NOMBRE    Con --inspeccionar: un archivo de otra app (p. ej. THQV8599). Se puede repetir.
      --idioma CÓDIGO    Idioma de los mensajes: es, en (por defecto, el del sistema).
      --ayuda            Muestra esta ayuda.

      Todas las opciones se aceptan también en inglés (--from, --to, --dest, --simulate…).

    ANTES DE EMPEZAR
      · iPhone: Ajustes → Apps → Fotos → Transferir a Mac o PC → «Conservar originales».
      · iPhone desbloqueado y conectado por cable; Captura de Imagen abierta y Fotos cerrada en el Mac.
    """

    init(argumentos: [String]) throws {
        self.init()
        var i = 0
        var modelos: [String] = []
        var desde: Date?
        var hasta: Date?
        func valor(_ opcion: String) throws -> String {
            i += 1
            guard i < argumentos.count else {
                throw ErrorHerramienta.argumentos(tr("Falta el valor de %@.", opcion))
            }
            return argumentos[i]
        }
        func ruta(_ texto: String) -> URL {
            URL(fileURLWithPath: (texto as NSString).expandingTildeInPath)
        }
        func fecha(_ opcion: String) throws -> Date {
            let v = try valor(opcion)
            guard let d = Configuracion.dia(v) else {
                throw ErrorHerramienta.argumentos(tr("%@ necesita una fecha AAAA-MM-DD: %@", opcion, v))
            }
            return d
        }

        while i < argumentos.count {
            let arg = argumentos[i]
            switch Configuracion.alias[arg] ?? arg {
            case "--lista": lista = ruta(try valor(arg))
            case "--destino": destino = ruta(try valor(arg))
            case "--simular": simular = true
            case "--modelo": modelos.append(try valor(arg))
            case "--sha256": opciones.sha256 = true
            case "--borrar": borrar = true
            case "--desde": desde = try fecha(arg)
            case "--hasta":
                let d = try fecha(arg)
                hasta = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: d)
            case "--inspeccionar": modo = .inspeccionar
            case "--volcar": modo = .volcar
            case "--ultimos":
                let v = try valor(arg)
                guard let n = Int(v), n > 0 else { throw ErrorHerramienta.argumentos(tr("%@ necesita un número: %@", arg, v)) }
                ultimos = n
            case "--numero":
                let v = try valor(arg)
                guard let n = ListaAlbum.numero(de: v) ?? Int(v) else {
                    throw ErrorHerramienta.argumentos(tr("%@ necesita algo como 1234 o IMG_1234: %@", arg, v))
                }
                numeros.append(n)
            case "--nombre":
                nombres.append(((try valor(arg)) as NSString).deletingPathExtension)
            case "--idioma":
                idioma = try valor(arg)
            case "--ayuda":
                print(Configuracion.ayuda)
                exit(0)
            default:
                throw ErrorHerramienta.argumentos(tr("Opción desconocida: %@", arg))
            }
            i += 1
        }

        if !modelos.isEmpty { opciones.camaras = modelos }
        if desde != nil || hasta != nil { opciones.periodo = .rango(desde: desde, hasta: hasta) }

        if modo == .transferir {
            guard lista != nil || desde != nil || hasta != nil else {
                throw ErrorHerramienta.argumentos(tr("Indica --desde/--hasta, o la lista del álbum con --lista (o usa --inspeccionar)."))
            }
            if let d = desde, let h = hasta, d > h {
                throw ErrorHerramienta.argumentos(tr("--desde es posterior a --hasta."))
            }
            if borrar && destino == nil {
                throw ErrorHerramienta.argumentos(tr("--borrar necesita --destino con la carpeta del respaldo."))
            }
            if !simular && destino == nil {
                throw ErrorHerramienta.argumentos(tr("Indica la carpeta de destino con --destino (o usa --simular)."))
            }
        }
    }
}
