import SwiftUI

/// Square placeholder shown wherever track/album artwork is missing — never
/// leave an empty rectangle. A music note on a quaternary fill.
public struct ArtworkPlaceholder: View {
    private let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 4) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
