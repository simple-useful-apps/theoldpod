import Foundation
import UniformTypeIdentifiers

/// Audio file formats accepted by the library importers and folder watchers.
/// Keep format checks centralized so picker imports and direct folder copies
/// behave the same way.
enum AudioFileSupport {
    static let supportedPathExtensions = ["mp3", "m4a"]

    #if os(macOS)
        static let importablePathExtensions = supportedPathExtensions + ["wma"]
    #else
        static let importablePathExtensions = supportedPathExtensions
    #endif

    static func supports(_ url: URL) -> Bool {
        supportedPathExtensions.contains(url.pathExtension.lowercased())
    }

    static func supportsImporting(_ url: URL) -> Bool {
        importablePathExtensions.contains(url.pathExtension.lowercased())
    }

    static var supportedContentTypes: [UTType] {
        var types: [UTType] = [.folder, .mp3, .mpeg4Audio]
        #if os(macOS)
            types.append(UTType(importedAs: "com.microsoft.windows-media-wma", conformingTo: .audio))
        #endif
        return types
    }
}
