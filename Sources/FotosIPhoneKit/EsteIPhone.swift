import Foundation
import FotosCore

/// El iPhone no dice su modelo por cable (solo su nombre, p. ej. «iPhone Strip»).
/// Se deduce de sus fotos: cada foto de la Cámara lleva el modelo en sus metadatos, y las más
/// recientes de un iPhone están hechas, casi siempre, con ese mismo iPhone.
@MainActor
public enum EsteIPhone {

    /// Modelo más frecuente entre las ~30 fotos de cámara de iPhone más recientes (nil si no hay).
    public static func deducir(_ catalogo: Catalogo, lector: LectorCamara) async -> String? {
        let recientes = catalogo.todosLosElementos
            .filter { $0.numero != nil && $0.imagenOriginal != nil }
            .sorted { ($0.fecha ?? .distantPast) > ($1.fecha ?? .distantPast) }
        var cuenta: [String: Int] = [:]
        var leidas = 0
        for el in recientes.prefix(120) {
            guard let img = el.imagenOriginal else { continue }
            let info = await lector.infoFoto(img)
            guard let modelo = info.model?.trimmingCharacters(in: .whitespaces),
                  info.make?.localizedCaseInsensitiveContains("Apple") ?? false,
                  modelo.localizedCaseInsensitiveContains("iPhone") else { continue }
            cuenta[modelo, default: 0] += 1
            leidas += 1
            if leidas >= 30 { break }
        }
        lector.guardar()
        return cuenta.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }

    /// Si las opciones piden «este iPhone», deduce el modelo y lo pone como cámara aceptada.
    /// Avisa del modelo deducido; falla si no hay fotos de cámara de las que deducirlo.
    public static func resolver(_ op: inout Opciones, catalogo: Catalogo, lector: LectorCamara,
                                observador: Observador) async throws {
        guard op.esteIPhone, op.origenes.contains(.camara) else { return }
        guard let modelo = await deducir(catalogo, lector: lector) else {
            throw ErrorHerramienta.argumentos(tr("No pude deducir el modelo de este iPhone (no encuentro fotos de su cámara). Elige el modelo con --modelo o usa --cualquier-camara."))
        }
        op.camaras = [modelo]
        op.modeloEsteIPhone = modelo
        observador(.mensaje(tr("📱 Este iPhone: %@ (deducido de sus fotos recientes).", modelo)))
    }
}
