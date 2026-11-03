import Foundation
import ImageCaptureCore
import FotosCore

/// Qué se borraría del iPhone y por qué. Se calcula sin tocar nada.
public struct PlanBorrado {
    /// Elementos con respaldo completo: se borrarían enteros.
    public internal(set) var aBorrar: [Elemento] = []
    /// Elementos sin nada en el respaldo: no se tocan.
    public internal(set) var noRespaldados: [Elemento] = []
    /// Elementos con respaldo a medias: no se tocan. Con lo que falta.
    public internal(set) var incompletos: [(elemento: Elemento, faltan: [String])] = []
    /// Archivos que se borran con su elemento aunque no estén en el respaldo
    /// (vídeo de la Live Photo, .AAE, .DAT) porque no se eligió copiarlos.
    public internal(set) var sinCopia: [Archivo] = []

    public var archivos: [Archivo] { aBorrar.flatMap(\.archivos) }
    public var bytes: Int64 { archivos.reduce(Int64(0)) { $0 + $1.tamano } }
}

/// Resultado de un borrado.
public struct ResultadoBorrado {
    public let borrados: Int
    public let fallidos: Int
    public let informe: URL
}

/// Borra del iPhone solo los elementos cuyo respaldo está completo en la carpeta de destino.
///
/// Un elemento cuenta como respaldado si están en el respaldo, con el mismo tamaño que en el iPhone,
/// **su foto o vídeo original y su versión editada, si la tiene**. Esta regla no depende de las
/// opciones de copia: así, por ejemplo, haber copiado solo la versión final nunca deja borrar el original.
/// Se buscan donde los apuntó el manifiesto, donde los pondría la organización elegida
/// y en la raíz del destino (respaldos de la v0.1).
///
/// Lo que no se eligió copiar (vídeo de la Live Photo, .AAE) se borra con su elemento, y el plan lo avisa.
@MainActor
public final class Borrado {
    let config: Configuracion
    let catalogo: Catalogo
    let camara: ICCameraDevice
    private let fm = FileManager.default
    private var manifiesto = Manifiesto()
    private let destino: URL
    /// Quién recibe los avisos (la Terminal imprime los mensajes; la app usa los eventos).
    public var observador: Observador = Observadores.terminal
    /// Para detener el borrado desde la app (se para al terminar el elemento en curso). nil en la Terminal.
    public var control: ControlCopia?
    /// La carpeta del respaldo que se comprueba.
    public var carpetaRespaldo: URL { destino }

    private func decir(_ texto: String) { observador(.mensaje(texto)) }

    public init(config: Configuracion, catalogo: Catalogo, camara: ICCameraDevice) {
        self.config = config
        self.catalogo = catalogo
        self.camara = camara
        self.destino = (config.destino ?? URL(fileURLWithPath: "/nonexistent")).standardizedFileURL
    }

    // MARK: Plan

    public func planificar() throws -> PlanBorrado {
        guard fm.fileExists(atPath: destino.path) else {
            throw ErrorHerramienta.argumentos(tr("No existe la carpeta del respaldo: %@", destino.path))
        }
        decir(tr("🗂  Comprobando el respaldo en %@\n", destino.path))
        manifiesto = Manifiesto.leer(en: destino)

        let candidatos = try catalogo.elementos(segun: config)
        if let informe = config.informe {
            decir(tr("📄 Según el informe %@: %ld elementos copiados que siguen en el iPhone.",
                     informe.lastPathComponent, candidatos.count))
        }
        var plan = PlanBorrado()
        for el in candidatos {
            let necesarios = Borrado.imprescindibles(el)
            guard !necesarios.isEmpty else {
                plan.noRespaldados.append(el)
                continue
            }
            var faltan: [String] = []
            for a in necesarios where ubicacion(a, en: el) == nil {
                faltan.append(a.nombre)
            }
            if faltan.isEmpty {
                plan.aBorrar.append(el)
                plan.sinCopia += el.archivos.filter { a in !necesarios.contains { $0 === a } && ubicacion(a, en: el) == nil }
            } else if faltan.count == necesarios.count {
                plan.noRespaldados.append(el)
            } else {
                plan.incompletos.append((el, faltan))
            }
        }
        return plan
    }

    /// Lo que tiene que estar en el respaldo para poder borrar el elemento: sus fotos (original
    /// y editada) o, si es un vídeo, sus vídeos. El vídeo de una Live Photo y los .AAE/.DAT no.
    static func imprescindibles(_ el: Elemento) -> [Archivo] {
        let esFoto = el.imagenOriginal != nil
        return el.archivos.filter { $0.clase == .imagen || ($0.clase == .video && !esFoto) }
    }

    /// Dónde está este archivo en el respaldo (con su tamaño exacto), o nil.
    private func ubicacion(_ a: Archivo, en el: Elemento) -> URL? {
        var candidatas: [String] = []
        if let r = manifiesto.ruta(de: a) { candidatas.append(r) }
        candidatas.append(Reglas.rutaRelativa(nombre: a.nombre, fecha: el.fecha, organizacion: config.opciones.organizacion))
        candidatas.append(a.nombre)   // raíz del destino (respaldos de la v0.1)
        for r in candidatas {
            let url = destino.appendingPathComponent(r)
            let tam = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
            if tam == a.tamano { return url }
        }
        return nil
    }

    /// Muestra el plan.
    public func mostrar(_ plan: PlanBorrado) {
        decir(tr("🧹 Se borrarían del iPhone %ld elementos (%ld archivos, %@).",
                 plan.aBorrar.count, plan.archivos.count, formatoBytes(plan.bytes)))
        if plan.aBorrar.count <= 20 {
            for el in plan.aBorrar {
                decir("   · \(el.etiqueta)  \(formatoFecha(el.fecha))  " + el.archivos.map(\.nombre).joined(separator: ", "))
            }
        }
        if !plan.sinCopia.isEmpty {
            let nombres = plan.sinCopia.prefix(8).map(\.nombre).joined(separator: ", ")
            decir(tr("   ⚠️  %ld archivos se borrarían con su elemento sin estar en el respaldo (vídeos de Live Photos, .AAE…): %@%@",
                     plan.sinCopia.count, nombres, plan.sinCopia.count > 8 ? "…" : ""))
            decir(tr("      Si los quieres conservar, cópialos antes (por ejemplo con --videos-live)."))
        }
        decir(tr("   No se tocan %ld elementos que no están en el respaldo.", plan.noRespaldados.count))
        if !plan.incompletos.isEmpty {
            decir(tr("   ⚠️  No se tocan %ld elementos con respaldo incompleto:", plan.incompletos.count))
            for i in plan.incompletos.prefix(20) {
                decir("      \(i.elemento.etiqueta): " + tr("falta %@", i.faltan.joined(separator: ", ")))
            }
            if plan.incompletos.count > 20 { decir("      …") }
        }
    }

    // MARK: Ejecución

    /// Borra del iPhone los elementos del plan, uno a uno, y guarda informe-borrado.csv.
    ///
    /// No se fía de la respuesta de ImageCaptureCore (en las pruebas dijo «borrado» de una foto que
    /// siguió en el iPhone): tras cada borrado comprueba en el catálogo del iPhone que los archivos
    /// desaparecieron de verdad, reintenta una vez lo que siga ahí, e informa solo de lo comprobado.
    public func ejecutar(_ plan: PlanBorrado) async -> ResultadoBorrado {
        var informe = "\u{FEFF}" + tr("elemento;archivo;resultado") + "\n"
        var borrados = 0
        var fallidos = 0
        for (i, el) in plan.aBorrar.enumerated() {
            if let control, control.cancelado {
                decir(tr("   ⏹  Borrado detenido: el resto no se ha tocado."))
                break
            }
            var pendientes = el.archivos
            var ultimoError: String?
            for _ in 0..<2 where !pendientes.isEmpty {
                do {
                    _ = try await camara.borrar(pendientes.map(\.file))
                } catch {
                    ultimoError = error.localizedDescription
                }
                pendientes = await esperarQueDesaparezcan(pendientes)
            }
            for a in el.archivos {
                let sigue = pendientes.contains { $0 === a }
                let resultado = sigue ? tr("sigue en el iPhone") : tr("borrado (comprobado)")
                informe += "\(el.etiqueta);\(a.nombre);\(resultado)\n"
                if sigue { fallidos += 1 } else { borrados += 1 }
            }
            observador(.borrando(indice: i + 1, total: plan.aBorrar.count, etiqueta: el.etiqueta,
                                 pendientes: pendientes.map(\.nombre)))
            let progreso = "[\(i + 1)/\(plan.aBorrar.count)]"
            if pendientes.isEmpty {
                decir(tr("   %@ ✓ %@ borrado (comprobado en el iPhone)", progreso, el.etiqueta))
            } else {
                let nota = ultimoError.map { " — \($0)" } ?? ""
                decir(tr("   %@ ✗ %@: sigue en el iPhone: %@", progreso, el.etiqueta,
                         pendientes.map(\.nombre).joined(separator: ", ")) + nota)
            }
        }
        let ruta = destino.appendingPathComponent("informe-borrado.csv")
        try? informe.write(to: ruta, atomically: true, encoding: .utf8)
        return ResultadoBorrado(borrados: borrados, fallidos: fallidos, informe: ruta)
    }

    /// Espera hasta 10 segundos a que los archivos salgan del catálogo del iPhone.
    /// Devuelve los que siguen ahí.
    private func esperarQueDesaparezcan(_ archivos: [Archivo]) async -> [Archivo] {
        var restantes = archivos
        for _ in 0..<20 {
            restantes = restantes.filter { sigueEnElIPhone($0) }
            if restantes.isEmpty { return [] }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return restantes.filter { sigueEnElIPhone($0) }
    }

    /// ¿Sigue este archivo en el catálogo actual del iPhone (como principal o como compañero)?
    /// Se compara por nombre, tamaño y fecha, no por el objeto, por si el catálogo se renovó.
    private func sigueEnElIPhone(_ a: Archivo) -> Bool {
        func igual(_ item: ICCameraItem) -> Bool {
            guard let f = item as? ICCameraFile else { return false }
            if f === a.file { return true }
            return f.name == a.nombre && Int64(f.fileSize) == a.tamano && f.creationDate == a.fecha
        }
        for item in camara.mediaFiles ?? [] {
            if igual(item) { return true }
            if let f = item as? ICCameraFile, (f.sidecarFiles ?? []).contains(where: igual) { return true }
        }
        return false
    }
}

private final class Fallidos: @unchecked Sendable {
    var nombres: [String] = []
}

extension ICCameraDevice {
    /// Borra archivos del iPhone. Devuelve los nombres de los que no se pudieron borrar.
    @MainActor
    func borrar(_ items: [ICCameraItem]) async throws -> [String] {
        let fallidos = Fallidos()
        return try await withCheckedThrowingContinuation { cont in
            _ = requestDeleteFiles(items, deleteFailed: { dic in
                fallidos.nombres += dic.values.compactMap { $0.name }
            }, completion: { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: fallidos.nombres)
                }
            })
        }
    }
}
