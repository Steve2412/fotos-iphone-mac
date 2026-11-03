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
        "--all": "--todo", "--days": "--dias", "--versions": "--versiones",
        "--no-aae": "--sin-aae", "--no-videos": "--sin-videos", "--max-video": "--video-max",
        "--live-videos": "--videos-live", "--sources": "--origenes", "--any-camera": "--cualquier-camara",
        "--layout": "--organizar", "--cameras": "--camaras",
        "--profile": "--perfil", "--save-profile": "--guardar-perfil", "--profiles": "--perfiles",
        "--wizard": "--asistente", "--yes": "--si",
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
      fotos-iphone                    (asistente: pregunta qué copiar)
      fotos-iphone --perfil Viaje --desde 2026-10-01 --hasta 2026-10-15 --destino ~/Pictures/Viaje
      fotos-iphone --desde 2026-01-01 --hasta 2026-01-31 --destino ~/Pictures/MiRespaldo [--simular]
      fotos-iphone --lista album.txt --destino ~/Pictures/Viaje [--simular]
      fotos-iphone --inspeccionar [--ultimos 30 | --numero 1234 --numero 1235 | --nombre THQV8599]

    OPCIONES
      --desde AAAA-MM-DD Copia lo hecho desde ese día (incluido).
      --hasta AAAA-MM-DD …hasta ese día (incluido). Se usa en lugar de --lista.
      --dias N           Los últimos N días (hoy incluido).
      --todo             Todo el iPhone.
      --lista RUTA       Lista del álbum generada por el Atajo
                         (una línea por elemento: IMG_1234|2026-10-20T14:33:12).
      --destino RUTA     Carpeta donde se guardan los archivos y el informe.csv.
      --simular          Muestra qué se copiaría y qué se descartaría, sin copiar nada.
      --borrar           Borra del iPhone lo que ya está completo en el respaldo de --destino
                         (original y editada). Pide escribir una clave; con --simular solo
                         muestra qué borraría. EXPERIMENTAL.
      --sha256           Añade al informe la huella SHA-256 de cada archivo copiado.
      --inspeccionar     Muestra cómo ve el Mac los archivos del iPhone (nombres, grupos, origen, cámara).
      --camaras          Cuenta los elementos por cámara y origen (en el periodo, o en todo el iPhone).
      --volcar           Guarda en catalogo-iphone.csv todos los archivos que muestra el iPhone (diagnóstico).
      --ultimos N        Con --inspeccionar: los N elementos más recientes (30 por defecto).
      --numero N         Solo el elemento IMG_N (o WIOR2185…) al inspeccionar, copiar o borrar.
                         Se copia sea del origen que sea. Se puede repetir.
      --nombre NOMBRE    Solo el archivo de otra app con ese nombre (p. ej. THQV8599). Se puede repetir.
      --si               Copia sin preguntar (por defecto se simula y se pide confirmación).
      --idioma CÓDIGO    Idioma de los mensajes: es, en (por defecto, el del sistema).
      --ayuda            Muestra esta ayuda.

    ASISTENTE Y PERFILES
      (sin opciones)     Asistente: pregunta qué copiar, paso a paso, y simula antes de copiar.
      --asistente        Lo mismo.
      --perfil NOMBRE    Usa las opciones de un perfil (las demás opciones lo modifican).
      --guardar-perfil NOMBRE  Guarda las opciones indicadas como perfil.
      --perfiles         Muestra los perfiles disponibles.

    QUÉ COPIAR (por defecto, como la v0.1: fotos y vídeos del iPhone 17 Pro, original + editada)
      --origenes LISTA   camara, capturas, grabaciones, apps (separados por comas) o todo.
      --modelo NOMBRE    Modelo de cámara aceptado. Se puede repetir.
      --cualquier-camara Acepta fotos y vídeos de cualquier cámara.
      --versiones V      originales (solo el original) · final (la editada si existe)
                         · ambas (original + editada).
      --sin-aae          Sin las instrucciones de edición (.AAE).
      --sin-videos       Sin vídeos.
      --video-max TAM    Descarta vídeos mayores que TAM (p. ej. 2GB, 500MB).
      --videos-live      Incluye los vídeos de las Live Photos.
      --raw MODO         incluir · excluir · solo (solo fotos RAW/DNG).
      --organizar MODO   plana (todo junto) · mes (2026/2026-10/) · dia (2026/2026-10/2026-10-20/).

      Todas las opciones se aceptan también en inglés (--from, --to, --dest, --simulate…).

    ANTES DE EMPEZAR
      · iPhone: Ajustes → Apps → Fotos → Transferir a Mac o PC → «Conservar originales».
      · iPhone desbloqueado y conectado por cable; Captura de Imagen abierta y Fotos cerrada en el Mac.
    """

    init(argumentos: [String]) throws {
        self.init()
        // Sin argumentos: el asistente pregunta todo.
        if argumentos.isEmpty {
            modo = .asistente
            return
        }
        var i = 0
        var modelos: [String] = []
        var desde: Date?
        var hasta: Date?
        var periodoDado = false
        var cualquierCamara = false
        var origenExplicito = false
        func invalido(_ opcion: String, _ v: String, _ validos: String) -> ErrorHerramienta {
            ErrorHerramienta.argumentos(tr("Valor no válido para %@: «%@». Valores posibles: %@.", opcion, v, validos))
        }
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
        // El perfil se aplica primero, para que las demás opciones lo puedan modificar.
        if let pos = argumentos.firstIndex(where: { $0 == "--perfil" || $0 == "--profile" }) {
            guard pos + 1 < argumentos.count else {
                throw ErrorHerramienta.argumentos(tr("Falta el valor de %@.", argumentos[pos]))
            }
            let nombre = argumentos[pos + 1]
            guard let p = Perfiles.buscar(nombre) else {
                throw ErrorHerramienta.argumentos(tr("No existe el perfil «%@». Mira los disponibles con --perfiles.", nombre))
            }
            perfil = p.nombre
            opciones = p.opciones
            destino = p.urlDestino
        }
        var destinoExplicito = false
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
            case "--destino":
                destino = ruta(try valor(arg))
                destinoExplicito = true
            case "--simular": simular = true
            case "--modelo":
                modelos.append(try valor(arg))
                origenExplicito = true
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
                if let n = ListaAlbum.numero(de: v) ?? Int(v) {
                    numeros.append(n)
                } else {
                    // No es un número IMG_: se entiende como nombre (p. ej. WIOR2185).
                    nombres.append((v as NSString).deletingPathExtension)
                }
            case "--nombre":
                nombres.append(((try valor(arg)) as NSString).deletingPathExtension)
            case "--idioma":
                idioma = try valor(arg)
            case "--todo":
                periodoDado = true
                opciones.periodo = .todo
            case "--dias":
                let v = try valor(arg)
                guard let n = Int(v), n > 0 else { throw ErrorHerramienta.argumentos(tr("%@ necesita un número: %@", arg, v)) }
                periodoDado = true
                opciones.periodo = .ultimosDias(n)
            case "--versiones":
                let v = try valor(arg)
                guard let x = Opciones.Versiones(texto: v) else { throw invalido(arg, v, tr("originales, final, ambas")) }
                opciones.versiones = x
            case "--sin-aae": opciones.aae = false
            case "--sin-videos": opciones.videos = false
            case "--video-max":
                let v = try valor(arg)
                guard let b = Opciones.bytes(v) else { throw invalido(arg, v, "2GB, 500MB") }
                opciones.videoMaximo = b
            case "--videos-live": opciones.videosLivePhoto = true
            case "--raw":
                let v = try valor(arg)
                guard let x = Opciones.ModoRAW(texto: v) else { throw invalido(arg, v, tr("incluir, excluir, solo")) }
                opciones.raw = x
            case "--origenes":
                origenExplicito = true
                let v = try valor(arg)
                guard let x = Opciones.Origen.conjunto(v) else { throw invalido(arg, v, tr("camara, capturas, grabaciones, apps, todo")) }
                opciones.origenes = x
            case "--cualquier-camara":
                cualquierCamara = true
                origenExplicito = true
            case "--organizar":
                let v = try valor(arg)
                guard let x = Opciones.Organizacion(texto: v) else { throw invalido(arg, v, tr("plana, mes, dia")) }
                opciones.organizacion = x
            case "--camaras": modo = .camaras
            case "--perfil": _ = try valor(arg)   // ya aplicado arriba
            case "--guardar-perfil": guardarPerfil = try valor(arg)
            case "--perfiles": modo = .perfiles
            case "--asistente": modo = .asistente
            case "--si": confirmar = false
            case "--ayuda":
                print(Configuracion.ayuda)
                exit(0)
            default:
                throw ErrorHerramienta.argumentos(tr("Opción desconocida: %@", arg))
            }
            i += 1
        }

        if cualquierCamara && !modelos.isEmpty {
            throw ErrorHerramienta.argumentos(tr("Usa --modelo o --cualquier-camara, no los dos."))
        }
        if !modelos.isEmpty { opciones.camaras = modelos }
        if cualquierCamara { opciones.camaras = nil }
        if desde != nil || hasta != nil {
            if periodoDado { throw ErrorHerramienta.argumentos(tr("Usa un solo periodo: --desde/--hasta, --dias o --todo.")) }
            opciones.periodo = .rango(desde: desde, hasta: hasta)
            periodoDado = true
        }

        // --guardar-perfil sin nada que hacer después: solo se guarda el perfil.
        if modo == .transferir, guardarPerfil != nil, !simular, !destinoExplicito, !periodoDado, lista == nil, !borrar {
            modo = .guardarPerfil
        }
        // Un perfil trae su periodo; si es «el rango que indiques» (Viaje), hay que darlo.
        if let nombre = perfil, modo == .transferir, !periodoDado, lista == nil,
           opciones.periodo == .rangoPorIndicar {
            throw ErrorHerramienta.argumentos(tr("El perfil «%@» copia el rango de fechas que indiques: añade --desde y --hasta.",
                                                 tr(nombre)))
        }
        if perfil != nil { periodoDado = true }

        // Elementos nombrados con --numero/--nombre: se copian sean del origen o cámara que sean,
        // salvo que se pida un filtro con --origenes, --modelo o --cualquier-camara (o un perfil).
        if (!numeros.isEmpty || !nombres.isEmpty), !origenExplicito, perfil == nil {
            opciones.origenes = Set(Opciones.Origen.allCases)
            opciones.camaras = nil
        }

        if modo == .transferir {
            guard lista != nil || periodoDado || !numeros.isEmpty || !nombres.isEmpty else {
                throw ErrorHerramienta.argumentos(tr("Indica el periodo (--desde/--hasta, --dias N o --todo), elementos concretos (--numero, --nombre) o la lista del álbum con --lista."))
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
