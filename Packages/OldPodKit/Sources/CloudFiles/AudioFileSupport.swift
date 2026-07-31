import Foundation

/// Audio file formats accepted by the library importers and folder watchers.
/// Keep format checks centralized so picker imports and direct folder copies
/// behave the same way.
public enum AudioFileSupport {
    public static let supportedPathExtensions = ["mp3", "m4a"]

    public static func supports(_ url: URL) -> Bool {
        supportedPathExtensions.contains(url.pathExtension.lowercased())
    }
}
