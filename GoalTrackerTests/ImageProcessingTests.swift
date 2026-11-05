import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import GoalTracker

struct ImageProcessingTests {
    private func jpeg(exif: [CFString: Any]?) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties = exif.map { [kCGImagePropertyExifDictionary: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func readsCaptureDateWithOffset() throws {
        let data = jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2019:06:15 14:30:00", kCGImagePropertyExifOffsetTimeOriginal: "-04:00"])
        let date = try #require(ImageProcessing.captureDate(of: data))
        #expect(date == ISO8601DateFormatter().date(from: "2019-06-15T18:30:00Z"))
    }

    @Test func missingMetadataReturnsNil() {
        #expect(ImageProcessing.captureDate(of: jpeg(exif: nil)) == nil)
    }

    private func photo(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func downsamplesToTheRequestedSizeKeepingAspect() throws {
        let image = try #require(ImageProcessing.downsampledImage(photo(width: 1200, height: 1600), maxPixelSize: 300))
        let pixels = try #require(image.cgImage)
        #expect(pixels.height == 300)
        #expect(pixels.width == 225)
    }

    @Test func cacheReturnsTheDecodedImage() async throws {
        let key = PhotoImageCache.key(for: UUID(), maxPixelSize: 300)
        #expect(PhotoImageCache.cached(key) == nil)
        let image = try #require(await PhotoImageCache.load(photo(width: 600, height: 800), key: key, maxPixelSize: 300))
        #expect(PhotoImageCache.cached(key) === image)
    }

    @Test func undecodableDataIsNil() {
        #expect(ImageProcessing.downsampledImage(Data("not an image".utf8), maxPixelSize: 300) == nil)
    }
}
