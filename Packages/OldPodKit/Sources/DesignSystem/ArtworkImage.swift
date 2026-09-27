import ImageIO
import SwiftUI

/// Renders artwork from the on-disk artwork cache (`<directory>/<id>.img`,
/// matching `MetadataImport.ArtworkStore.fileURL(for:in:)`'s filename
/// convention — duplicated inline here rather than depending on
/// `MetadataImport`, since `DesignSystem` is dependency-free by design),
/// falling back to `ArtworkPlaceholder` whenever there's no id, no directory,
/// or the load fails or is still in flight.
///
/// Loads a *downsampled* thumbnail rather than the full-resolution image:
/// artwork files can be a few megabytes, and decoding one at full size just
/// to draw it into a 40pt row icon wastes memory and time. `pointSize` (in
/// points; converted to pixels via the environment's `displayScale`) tells
/// the loader how large a thumbnail to decode.
public struct ArtworkImage: View {
    private let artworkID: String?
    private let directory: URL?
    private let cornerRadius: CGFloat
    private let pointSize: CGFloat
    private let placeholderSystemName: String

    @Environment(\.displayScale) private var displayScale
    @State private var cgImage: CGImage?

    public init(
        artworkID: String?,
        directory: URL?,
        cornerRadius: CGFloat = 4,
        pointSize: CGFloat = 44,
        placeholderSystemName: String = "music.note"
    ) {
        self.artworkID = artworkID
        self.directory = directory
        self.cornerRadius = cornerRadius
        self.pointSize = pointSize
        self.placeholderSystemName = placeholderSystemName
    }

    public var body: some View {
        Group {
            if let cgImage {
                Image(decorative: cgImage, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkPlaceholder(cornerRadius: cornerRadius, systemName: placeholderSystemName)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: LoadKey(url: url, pixelSize: pixelSize)) {
            cgImage = await ArtworkThumbnailLoader.thumbnail(at: url, maxPixelSize: pixelSize)
        }
    }

    private var url: URL? {
        guard let artworkID, let directory else { return nil }
        return directory.appendingPathComponent("\(artworkID).img")
    }

    private var pixelSize: Int {
        max(1, Int((pointSize * displayScale).rounded(.up)))
    }

    /// Identifies one loader request: a new value (different url or, e.g.,
    /// screen change altering `displayScale`) restarts `.task`.
    private struct LoadKey: Equatable {
        let url: URL?
        let pixelSize: Int
    }
}

/// Decodes a downsampled thumbnail off the main actor and caches it by
/// `url` + `maxPixelSize`, so scrolling back to a row already rendered
/// doesn't re-decode its artwork.
private enum ArtworkThumbnailLoader {
    /// NSCache is internally thread-safe; the cache is read/written from
    /// whatever detached background task happens to be decoding, so this
    /// is documented `nonisolated(unsafe)` rather than actor-isolated.
    private nonisolated(unsafe) static let cache = NSCache<NSString, CGImage>()

    static func thumbnail(at url: URL?, maxPixelSize: Int) async -> CGImage? {
        guard let url else { return nil }
        let key = "\(url.path)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            cache.setObject(thumbnail, forKey: key)
            return thumbnail
        }.value
    }
}
