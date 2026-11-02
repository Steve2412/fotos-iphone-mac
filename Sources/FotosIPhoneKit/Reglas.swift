import Foundation
import AVFoundation
import FotosCore

// Las reglas están en FotosCore. Aquí solo queda lo que necesita AVFoundation.

extension DatosCamara {
    /// Lee fabricante y modelo de un vídeo QuickTime ya copiado al Mac.
    static func makeModelDeVideo(_ url: URL) async -> (make: String?, model: String?) {
        let asset = AVURLAsset(url: url)
        var items: [AVMetadataItem] = []
        if let m = try? await asset.load(.metadata) { items += m }
        if let q = try? await asset.loadMetadata(for: .quickTimeMetadata) { items += q }
        let todos = items

        func texto(_ ids: [AVMetadataIdentifier]) async -> String? {
            for id in ids {
                for item in AVMetadataItem.metadataItems(from: todos, filteredByIdentifier: id) {
                    if let s = try? await item.load(.stringValue), !s.isEmpty { return s }
                }
            }
            return nil
        }
        let make = await texto([.quickTimeMetadataMake, .commonIdentifierMake])
        let model = await texto([.quickTimeMetadataModel, .commonIdentifierModel])
        return (make, model)
    }
}
