#if os(macOS)
    import CloudFiles
    import CoreGraphics
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers

    struct ArtworkImagePreparerTests {
        @Test func aLargePNGBecomesAJPEGCappedOnItsLongestSide() throws {
            let png = try encodedImage(width: 3000, height: 1500, type: .png)

            let jpeg = try ArtworkImagePreparer.jpegData(from: png)

            let (type, width, height) = try properties(of: jpeg)
            #expect(type == UTType.jpeg.identifier)
            #expect(width == ArtworkImagePreparer.maxPixelSize)
            #expect(height == ArtworkImagePreparer.maxPixelSize / 2)
        }

        @Test func aSmallPictureKeepsItsSize() throws {
            let png = try encodedImage(width: 300, height: 300, type: .png)

            let jpeg = try ArtworkImagePreparer.jpegData(from: png)

            let (type, width, height) = try properties(of: jpeg)
            #expect(type == UTType.jpeg.identifier)
            #expect(width == 300)
            #expect(height == 300)
        }

        @Test func aFileOnDiskIsReadThroughItsURL() throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: url) }
            try encodedImage(width: 64, height: 64, type: .png).write(to: url)

            let jpeg = try ArtworkImagePreparer.jpegData(contentsOf: url)

            #expect(try properties(of: jpeg).width == 64)
        }

        @Test func somethingThatIsNotAPictureIsRejected() {
            #expect(throws: ArtworkImagePreparer.Failure.self) {
                try ArtworkImagePreparer.jpegData(from: Data("not an image".utf8))
            }
        }
    }

    private func encodedImage(width: Int, height: Int, type: UTType) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output as CFMutableData, type.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(of data: Data) throws -> (type: String, width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source)) as String
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        return (type, width, height)
    }
#endif
