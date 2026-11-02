import Foundation

public func formatoBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}

private let formateadorFecha: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

public func formatoFecha(_ d: Date?) -> String {
    d.map { formateadorFecha.string(from: $0) } ?? tr("sin fecha")
}
