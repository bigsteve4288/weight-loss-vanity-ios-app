import ImageIO
import UIKit

enum ImageProcessing {
    /// When the photo was taken, from its EXIF/TIFF metadata. Nil if the file carries no date.
    static func captureDate(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let stamp = (exif?[kCGImagePropertyExifDateTimeOriginal] ?? exif?[kCGImagePropertyExifDateTimeDigitized] ?? tiff?[kCGImagePropertyTIFFDateTime]) as? String
        else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: stamp + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: stamp)
    }

    /// Re-encodes image data as JPEG with its longest side capped at `maxDimension` points.
    static func downscaledJPEG(_ data: Data, maxDimension: CGFloat, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

extension ImageProcessing {
    /// Decodes a photo straight to at most `maxPixelSize` on its longest side, without first decoding it at
    /// full size. Much cheaper than `UIImage(data:)` for thumbnails.
    static func downsampledImage(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Decoded progress photos kept in memory, so switching tabs and re-rendering don't decode JPEGs again.
/// Decoding happens off the main thread. `NSCache` is thread-safe and drops entries under memory pressure.
enum PhotoImageCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func key(for id: some Hashable, maxPixelSize: CGFloat) -> String {
        "\(id.hashValue)-\(Int(maxPixelSize))"
    }

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func load(_ data: Data, key: String, maxPixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(key) { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            ImageProcessing.downsampledImage(data, maxPixelSize: maxPixelSize)
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }
}
