import DesignSystem
import SwiftUI

/// M0 placeholder shown by both apps until the library UI lands in M1/M3.
public struct WelcomeView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("theoldpod")
                .font(.largeTitle.weight(.semibold))
            Text("Your music. Your files.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 320)
        #endif
    }
}
