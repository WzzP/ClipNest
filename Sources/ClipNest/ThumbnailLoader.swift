import Foundation
import ImageIO
import UniformTypeIdentifiers

// A serial background actor keeps disk reads and image decoding off the UI thread.
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSData>()

    func load(url: URL, maxPixelSize: Int) -> Data? {
        let key = "\(url.path)-\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.setObject(data, forKey: key, cost: data.length)
        return data as Data
    }
}
