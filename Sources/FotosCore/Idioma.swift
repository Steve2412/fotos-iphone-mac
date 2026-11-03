import Foundation

/// Traducción de los textos de la herramienta.
///
/// · Las claves son el propio texto en español (p. ej. «✅ Catálogo completo.»).
///   Si falta una traducción (o la carpeta de recursos), se muestra el español.
/// · Cada idioma es una carpeta `Resources/<código>.lproj/Localizable.strings`.
///   Para añadir uno: copiar `en.lproj` con el código nuevo (p. ej. `fr.lproj`),
///   traducir los valores (lo que va a la derecha del `=`) y recompilar.
/// · Por defecto se usa el idioma del sistema; `Idioma.elegir("en")` lo fuerza.
public enum Idioma {
    private static var tabla: Bundle?
    private static var codigo = "es"
    private static var listo = false

    /// Elige el idioma por su código («en», «es»…) o, con nil, el del sistema.
    /// Devuelve el código del idioma que se usará.
    @discardableResult
    public static func elegir(_ preferido: String?) -> String {
        listo = true
        tabla = nil
        codigo = "es"
        guard let recursos = recursos else { return codigo }
        let preferencias = preferido.map { [$0] } ?? Locale.preferredLanguages
        let elegido = Bundle.preferredLocalizations(from: disponibles, forPreferences: preferencias).first ?? "es"
        codigo = elegido
        if let ruta = recursos.path(forResource: elegido, ofType: "lproj") {
            tabla = Bundle(path: ruta)
        }
        return codigo
    }

    /// Código del idioma en uso.
    public static var actual: String {
        if !listo { elegir(nil) }
        return codigo
    }

    /// Idiomas que tienen carpeta de traducción.
    public static var disponibles: [String] {
        (recursos?.localizations ?? ["es"]).filter { $0 != "Base" }.sorted()
    }

    /// Texto traducido de una clave (el texto en español), o `porDefecto` si no hay traducción.
    public static func texto(_ clave: String, porDefecto: String? = nil) -> String {
        if !listo { elegir(nil) }
        let respaldo = porDefecto ?? clave
        return tabla?.localizedString(forKey: clave, value: respaldo, table: nil) ?? respaldo
    }

    /// Texto de una clave en un idioma concreto (sin cambiar el idioma en uso).
    public static func texto(_ clave: String, enIdioma idioma: String) -> String {
        guard let ruta = recursos?.path(forResource: idioma, ofType: "lproj"),
              let tabla = Bundle(path: ruta) else { return clave }
        return tabla.localizedString(forKey: clave, value: clave, table: nil)
    }

    // MARK: Carpeta de recursos

    /// Nombre con el que SwiftPM empaqueta los recursos de FotosCore.
    static let nombreRecursos = "fotos-iphone_FotosCore.bundle"
    private final class Marcador {}

    /// Se busca a mano (y no con `Bundle.module`, que cierra el programa si no la encuentra):
    /// junto al ejecutable, en los recursos de una app, o junto al paquete de pruebas.
    static let recursos: Bundle? = {
        var candidatos: [URL] = []
        if let r = Bundle.main.resourceURL { candidatos.append(r) }
        candidatos.append(Bundle.main.bundleURL)
        candidatos.append(Bundle(for: Marcador.self).bundleURL.deletingLastPathComponent())
        if let exe = Bundle.main.executableURL {
            candidatos.append(exe.resolvingSymlinksInPath().deletingLastPathComponent())
        }
        for c in candidatos {
            if let b = Bundle(url: c.appendingPathComponent(nombreRecursos)) { return b }
        }
        return nil
    }()
}

/// Traduce `clave` (texto en español) y, si hay argumentos, los coloca con `String(format:)`.
/// Formatos: %@ para textos, %ld para Int, %lld para Int64.
public func tr(_ clave: String, _ args: CVarArg...) -> String {
    let formato = Idioma.texto(clave)
    guard !args.isEmpty else { return formato }
    return String(format: formato, locale: Locale(identifier: Idioma.actual), arguments: args)
}
