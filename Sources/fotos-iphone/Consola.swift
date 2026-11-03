import Foundation
import FotosCore

/// Preguntas en Terminal. La lectura se hace en otro hilo para no bloquear el bucle principal,
/// donde ImageCaptureCore sigue entregando sus avisos mientras esperamos la respuesta.
/// Escribir «q» (o cerrar la entrada) cancela.
@MainActor
enum Consola {

    /// Lee una línea; nil si se cerró la entrada.
    static func leer(_ pregunta: String) async -> String? {
        print(pregunta, terminator: "")
        fflush(stdout)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: readLine())
            }
        }
    }

    /// Texto libre. Intro deja `porDefecto`.
    static func texto(_ pregunta: String, porDefecto: String? = nil) async throws -> String {
        let pista = (porDefecto?.isEmpty ?? true) ? "" : " [\(porDefecto!)]"
        while true {
            guard let r = await leer("\(pregunta)\(pista): ") else { throw ErrorHerramienta.cancelado }
            let t = r.trimmingCharacters(in: .whitespaces)
            if esSalir(t) { throw ErrorHerramienta.cancelado }
            if t.isEmpty {
                if let porDefecto { return porDefecto }
                continue
            }
            return t
        }
    }

    /// Sí o no. Acepta s/si/sí/y/yes y n/no.
    static func siNo(_ pregunta: String, porDefecto: Bool) async throws -> Bool {
        let pista = porDefecto ? tr("S/n") : tr("s/N")
        while true {
            guard let r = await leer("\(pregunta) [\(pista)]: ") else { throw ErrorHerramienta.cancelado }
            let t = normalizarRespuesta(r)
            if esSalir(t) { throw ErrorHerramienta.cancelado }
            if t.isEmpty { return porDefecto }
            if ["s", "si", "y", "yes"].contains(t) { return true }
            if ["n", "no"].contains(t) { return false }
            print(tr("   Responde s o n (q para salir)."))
        }
    }

    /// Una opción de una lista numerada. Devuelve su posición (desde 0).
    static func elegir(_ titulo: String, _ opciones: [String], porDefecto: Int) async throws -> Int {
        print("\n" + titulo)
        for (i, o) in opciones.enumerated() {
            print("   \(i + 1)) \(o)" + (i == porDefecto ? tr("  ← actual") : ""))
        }
        while true {
            let t = try await texto(tr("   Número"), porDefecto: String(porDefecto + 1))
            if let n = Int(t), n >= 1, n <= opciones.count { return n - 1 }
            print(tr("   Escribe un número del 1 al %ld.", opciones.count))
        }
    }

    /// Varias opciones de una lista numerada («1,3»). Devuelve sus posiciones (desde 0).
    static func varias(_ titulo: String, _ opciones: [String], marcadas: Set<Int>) async throws -> Set<Int> {
        print("\n" + titulo)
        for (i, o) in opciones.enumerated() {
            print("   \(i + 1)) [\(marcadas.contains(i) ? "x" : " ")] \(o)")
        }
        let actual = marcadas.sorted().map { String($0 + 1) }.joined(separator: ",")
        while true {
            let t = try await texto(tr("   Números separados por comas"), porDefecto: actual.isEmpty ? nil : actual)
            let partes = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let numeros = partes.compactMap { Int($0) }
            if numeros.count == partes.count, !numeros.isEmpty, numeros.allSatisfy({ $0 >= 1 && $0 <= opciones.count }) {
                return Set(numeros.map { $0 - 1 })
            }
            print(tr("   Escribe uno o varios números del 1 al %ld, separados por comas.", opciones.count))
        }
    }

    private static func normalizarRespuesta(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func esSalir(_ t: String) -> Bool {
        ["q", "salir", "quit", "exit"].contains(normalizarRespuesta(t))
    }
}
