import CloudFiles
import Foundation

/// Tracks which conversion may still change a metadata editor's artwork.
public struct ArtworkSelection {
    public private(set) var change: AudioArtworkChange = .keep
    public private(set) var pendingRequest: UUID?

    public init() {}

    public var isProcessing: Bool {
        pendingRequest != nil
    }

    public mutating func begin() -> UUID {
        let request = UUID()
        pendingRequest = request
        return request
    }

    /// Returns false for results (including errors) superseded by another choice.
    @discardableResult
    public mutating func finish(_ request: UUID, data: Data?) -> Bool {
        guard pendingRequest == request else { return false }
        pendingRequest = nil
        if let data { change = .replace(data) }
        return true
    }

    public mutating func remove() {
        pendingRequest = nil
        change = .remove
    }

    public mutating func invalidate() {
        pendingRequest = nil
    }

    /// A snapshot for an asynchronous save; nil while the choice is unresolved.
    public var saveSnapshot: AudioArtworkChange? {
        isProcessing ? nil : change
    }
}
