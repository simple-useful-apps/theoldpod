import SwiftUI

/// Renders artwork from the on-disk artwork cache (`<directory>/<id>.img`,
/// matching `MetadataImport.ArtworkStore`'s filename convention), falling
/// back to `ArtworkPlaceholder` whenever there's no id, no directory, or the
/// load fails or is still in flight.
public struct ArtworkImage: View {
    private let artworkID: String?
    private let directory: URL?
    private let cornerRadius: CGFloat

    public init(artworkID: String?, directory: URL?, cornerRadius: CGFloat = 4) {
        self.artworkID = artworkID
        self.directory = directory
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ArtworkPlaceholder(cornerRadius: cornerRadius)
                    }
                }
            } else {
                ArtworkPlaceholder(cornerRadius: cornerRadius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var url: URL? {
        guard let artworkID, let directory else { return nil }
        return directory.appendingPathComponent("\(artworkID).img")
    }
}
