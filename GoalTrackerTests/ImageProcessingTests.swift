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
}
