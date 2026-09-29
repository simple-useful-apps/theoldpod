#if os(macOS)
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Turns any picture the user chooses (JPEG, PNG, HEIC, TIFF…) into the
    /// one form The Old Pod embeds: an upright JPEG no larger than
    /// `maxPixelSize` on its longest side. One format keeps the tag writer
    /// simple, and the size cap keeps a phone photo from adding megabytes to
    /// every track of an album.
    public enum ArtworkImagePreparer {
        public static let maxPixelSize = 1200

        public enum Failure: LocalizedError, Sendable {
            case unreadableImage

            public var errorDescription: String? {
                "That file isn’t a picture The Old Pod can read."
            }
        }

        public static func jpegData(contentsOf url: URL) throws -> Data {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure.unreadableImage }
            return try jpegData(from: source)
        }

        public static func jpegData(from data: Data) throws -> Data {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadableImage }
            return try jpegData(from: source)
        }

        private static func jpegData(from source: CGImageSource) throws -> Data {
            guard CGImageSourceGetCount(source) > 0 else { throw Failure.unreadableImage }
            // The thumbnail API applies EXIF orientation and only ever
            // scales down, so small pictures keep their own size.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw Failure.unreadableImage
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
            ) else { throw Failure.unreadableImage }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { throw Failure.unreadableImage }
            return output as Data
        }
    }
#endif
