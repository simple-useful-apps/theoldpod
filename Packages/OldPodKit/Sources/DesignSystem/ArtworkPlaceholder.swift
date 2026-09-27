import SwiftUI

/// Square placeholder shown wherever artwork is missing — never leave an
/// empty rectangle. A context-appropriate system symbol on a quaternary fill.
public struct ArtworkPlaceholder: View {
    private let cornerRadius: CGFloat
    private let systemName: String

    public init(cornerRadius: CGFloat = 4, systemName: String = "music.note") {
        self.cornerRadius = cornerRadius
        self.systemName = systemName
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: systemName)
                    .foregroundStyle(.secondary)
            }
            .aspectRatio(1, contentMode: .fit)
    }
}
