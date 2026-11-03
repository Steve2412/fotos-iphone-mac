import Foundation
import FotosCore
import FotosIPhoneKit

/// Asistente de Terminal: pregunta qué copiar, paso a paso, con lo elegido la última vez
/// (o lo de un perfil) como respuesta por defecto. Al final simula, muestra el resumen
/// y pide confirmación antes de copiar.
@MainActor
final class Asistente {
    let config: Configuracion
    let catalogo: Catalogo

    init(config: Configuracion, catalogo: Catalogo) {
        self.config = config
        self.catalogo = catalogo
    }

    func ejecutar() async throws {
        print(tr("🧭 Asistente: te pregunto qué copiar. Intro acepta lo que aparece entre corchetes; q cancela."))
        let ultima = Perfiles.ultima()
        var op = ultima?.opciones ?? Opciones()
        var destino = ultima?.destino ?? "~/Pictures/iPhone"

        // 1. ¿Un perfil de partida?
        let perfiles = Perfiles.todos()
        let nombres = [tr("Configurar paso a paso (partiendo de lo elegido la última vez)")]
            + perfiles.map { $0.nombreVisible + (Perfiles.esIntegrado($0) ? "" : tr(" (guardado)")) }
        let elegido = try await Consola.elegir(tr("👤 ¿Partimos de un perfil?"), nombres, porDefecto: 0)
        var preguntarTodo = true
        if elegido > 0 {
            let p = perfiles[elegido - 1]
            op = p.opciones
            if let d = p.destino { destino = d }
            print(tr("\nPerfil «%@»:", p.nombreVisible))
            for l in op.resumen { print("   · " + l) }
            preguntarTodo = try await Consola.siNo(tr("¿Quieres cambiar alguna opción además del periodo?"), porDefecto: false)
        }

        // 2. Periodo (siempre) y el resto de opciones.
        op.periodo = try await preguntarPeriodo(op.periodo)
        if preguntarTodo {
            try await preguntarOpciones(&op)
        }

        // 3. Destino.
        let carpeta = try await preguntarDestino(destino)
        destino = carpeta.texto
        let urlDestino = carpeta.url

        // 4. Resumen y, si se quiere, guardar como perfil.
        print(tr("\n⚙️  Resumen:"))
        for l in op.resumen { print("   · " + l) }
        print("   · " + tr("Destino: %@", urlDestino.path))
        let nombre = try await Consola.texto(tr("\n💾 ¿Guardar estas opciones como perfil? Escribe un nombre (Intro para no guardar)"),
                                             porDefecto: "")
        if !nombre.isEmpty {
            let existia = Perfiles.buscar(nombre) != nil
            if existia {
                let sustituir = try await Consola.siNo(tr("   Ya existe el perfil «%@». ¿Actualizarlo con estas opciones?", nombre), porDefecto: true)
                if sustituir {
                    let nombreReal = Perfiles.buscar(nombre)?.nombre ?? nombre
                    try Perfiles.guardar(Perfil(nombre: nombreReal, opciones: op.sinDeducciones, destino: destino))
                    print(tr("   ✅ Perfil «%@» actualizado.", tr(nombreReal)))
                }
            } else {
                try Perfiles.guardar(Perfil(nombre: nombre, opciones: op.sinDeducciones, destino: destino))
                print(tr("   ✅ Perfil «%@» guardado. La próxima vez: --perfil \"%@\"", nombre, nombre))
            }
        }
        Perfiles.guardarUltima(Perfil(nombre: "ultima-vez", opciones: op, destino: destino))

        // 5. Simular, confirmar y copiar.
        print("")
        var c = config
        c.modo = .transferir
        c.lista = nil
        c.opciones = op
        c.destino = urlDestino
        c.simular = false
        c.confirmar = true
        try await Copia.simularYCopiar(c, catalogo: catalogo)
    }

    // MARK: Preguntas

    /// Pide la carpeta de destino hasta que sea una en la que se pueda escribir.
    /// Sin «/» ni «~» al principio se entiende dentro de la carpeta personal (Desktop/x → ~/Desktop/x).
    private func preguntarDestino(_ actual: String) async throws -> (texto: String, url: URL) {
        var porDefecto = actual
        while true {
            var texto = try await Consola.texto(tr("\n📂 Carpeta de destino (p. ej. ~/Pictures/iPhone)"), porDefecto: porDefecto)
            if !texto.hasPrefix("/") && !texto.hasPrefix("~") { texto = "~/" + texto }
            let url = URL(fileURLWithPath: (texto as NSString).expandingTildeInPath).standardizedFileURL
            if Disco.sePuedeEscribir(en: url) { return (texto, url) }
            print(tr("   No se puede escribir en %@.", url.path))
            // ¿Faltaba el ~? («/Desktop/x» → «~/Desktop/x»)
            if texto.hasPrefix("/") {
                let enCasa = "~" + texto
                let url2 = URL(fileURLWithPath: (enCasa as NSString).expandingTildeInPath).standardizedFileURL
                if Disco.sePuedeEscribir(en: url2),
                   try await Consola.siNo(tr("   ¿Quisiste decir %@ (%@)?", enCasa, url2.path), porDefecto: true) {
                    return (enCasa, url2)
                }
            }
            porDefecto = "~/Pictures/iPhone"
        }
    }

    private func preguntarPeriodo(_ actual: Opciones.Periodo) async throws -> Opciones.Periodo {
        let porDefecto: Int
        switch actual {
        case .todo: porDefecto = 0
        case .ultimosDias: porDefecto = 1
        case .mesAnterior: porDefecto = 2
        case .rango: porDefecto = 3
        }
        let i = try await Consola.elegir(tr("📅 ¿Qué periodo?"),
                                         [tr("Todo el iPhone"), tr("Los últimos días"),
                                          tr("El mes pasado (%@)", Opciones.Periodo.textoMesAnterior()),
                                          tr("Entre dos fechas")],
                                         porDefecto: porDefecto)
        switch i {
        case 0:
            return .todo
        case 2:
            return .mesAnterior
        case 1:
            var dias = 7
            if case .ultimosDias(let n) = actual { dias = n }
            while true {
                let t = try await Consola.texto(tr("   ¿Cuántos días? (hoy incluido)"), porDefecto: String(dias))
                if let n = Int(t), n > 0 { return .ultimosDias(n) }
                print(tr("   Escribe un número mayor que 0."))
            }
        default:
            var desde = Date(), hasta = Date()
            if case .rango(let d, let h) = actual {
                desde = d ?? desde
                hasta = h ?? hasta
            }
            while true {
                let d = try await fecha(tr("   Desde (AAAA-MM-DD)"), porDefecto: desde)
                let h = try await fecha(tr("   Hasta (AAAA-MM-DD, incluido)"), porDefecto: hasta)
                // «Hasta» incluye todo ese día.
                let finDelDia = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1),
                                                      to: Calendar.current.startOfDay(for: h)) ?? h
                if d <= finDelDia { return .rango(desde: Calendar.current.startOfDay(for: d), hasta: finDelDia) }
                print(tr("   La fecha inicial es posterior a la final."))
            }
        }
    }

    private func fecha(_ pregunta: String, porDefecto: Date) async throws -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        while true {
            let t = try await Consola.texto(pregunta, porDefecto: f.string(from: porDefecto))
            if let d = Configuracion.dia(t) { return d }
            print(tr("   Escribe la fecha como AAAA-MM-DD, por ejemplo 2026-10-31."))
        }
    }

    private func preguntarOpciones(_ op: inout Opciones) async throws {
        // Orígenes
        let origenes = Opciones.Origen.allCases
        let marcados = Set(origenes.indices.filter { op.origenes.contains(origenes[$0]) })
        let elegidos = try await Consola.varias(tr("📸 ¿Qué incluir?"), origenes.map(\.texto), marcadas: marcados)
        op.origenes = Set(elegidos.map { origenes[$0] })

        // Cámaras
        if op.origenes.contains(.camara) {
            let modelo = await EsteIPhone.deducir(catalogo, lector: LectorCamara())
            let textoEste = modelo.map { tr("Solo de este iPhone (%@, deducido de sus fotos recientes)", $0) }
                ?? tr("Solo de este iPhone (se deduce de sus fotos recientes)")
            let i = try await Consola.elegir(tr("📷 ¿De qué cámaras?"),
                                             [textoEste,
                                              tr("De cualquier cámara"),
                                              tr("Elegir entre las cámaras del periodo (la primera vez tarda: lee cada foto)")],
                                             porDefecto: op.esteIPhone ? 0 : (op.camaras == nil ? 1 : 2))
            if i == 0 {
                op.esteIPhone = true
                op.camaras = nil
            } else if i == 1 {
                op.esteIPhone = false
                op.camaras = nil
            } else {
                op.esteIPhone = false
                let conteos = await ListaCamaras(config: config, catalogo: catalogo)
                    .contar(en: op.periodo).filter { $0.modelo != nil }
                if conteos.isEmpty {
                    print(tr("   No hay fotos ni vídeos de cámara en ese periodo; se acepta cualquier cámara."))
                    op.camaras = nil
                } else {
                    let actuales = op.camaras ?? []
                    var marcadas = Set(conteos.indices.filter { i in
                        actuales.contains { $0.caseInsensitiveCompare(conteos[i].modelo!) == .orderedSame }
                    })
                    if marcadas.isEmpty { marcadas = [0] }
                    let textos = conteos.map { tr("%@  (%ld fotos, %ld vídeos)", $0.etiqueta, $0.fotos, $0.videos) }
                    let sel = try await Consola.varias(tr("📷 Cámaras encontradas en el periodo:"), textos, marcadas: marcadas)
                    op.camaras = sel.sorted().compactMap { conteos[$0].modelo }
                }
            }
        }

        // Versiones y .AAE
        let versiones = Opciones.Versiones.allCases
        let v = try await Consola.elegir(tr("✏️  De lo editado, ¿qué versión copiar?"), versiones.map(\.texto),
                                         porDefecto: versiones.firstIndex(of: op.versiones) ?? 2)
        op.versiones = versiones[v]
        if op.versiones == .originalYEditada {
            op.aae = try await Consola.siNo(tr("   ¿Incluir las instrucciones de edición (.AAE)?"), porDefecto: op.aae)
        }

        // Vídeos
        op.videos = try await Consola.siNo(tr("\n🎬 ¿Incluir vídeos?"), porDefecto: op.videos)
        if op.videos {
            while true {
                let actual = op.videoMaximo.map { formatoBytes($0) } ?? ""
                let t = try await Consola.texto(tr("   Tamaño máximo por vídeo (p. ej. 2GB; 0 = sin límite)"),
                                                porDefecto: actual.isEmpty ? "0" : actual)
                if t.isEmpty || t == "0" || ["no", "sin", "none"].contains(t.lowercased()) { op.videoMaximo = nil; break }
                if let b = Opciones.bytes(t) { op.videoMaximo = b; break }
                print(tr("   No entiendo ese tamaño. Ejemplos: 2GB, 500MB."))
            }
        }
        op.videosLivePhoto = try await Consola.siNo(tr("   ¿Incluir los vídeos de las Live Photos?"), porDefecto: op.videosLivePhoto)

        // RAW
        let raws = Opciones.ModoRAW.allCases
        let r = try await Consola.elegir(tr("🎞  Fotos RAW (DNG):"), raws.map(\.texto),
                                         porDefecto: raws.firstIndex(of: op.raw) ?? 0)
        op.raw = raws[r]

        // Organización
        let organizaciones = Opciones.Organizacion.allCases
        let o = try await Consola.elegir(tr("🗂  ¿Cómo organizar las carpetas del destino?"), organizaciones.map(\.texto),
                                         porDefecto: organizaciones.firstIndex(of: op.organizacion) ?? 0)
        op.organizacion = organizaciones[o]
    }
}
