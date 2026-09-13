import Foundation
import ImageIO
@main struct CheckThumbnail {
    static func main() async {
        let url = URL(fileURLWithPath: ".build/checks/TestIcon.iconset/icon_512x512@2x.png")
        let data = await ThumbnailLoader.shared.load(url: url, maxPixelSize: 440)
        precondition(data != nil)
        let source = CGImageSourceCreateWithData(data! as CFData, nil)!
        let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        precondition((info[kCGImagePropertyPixelWidth] as! Int) == 440)
        precondition((info[kCGImagePropertyPixelHeight] as! Int) == 440)
        let cached = await ThumbnailLoader.shared.load(url: url, maxPixelSize: 440)
        precondition(cached == data)
        let missing = await ThumbnailLoader.shared.load(url: URL(fileURLWithPath: ".build/missing-thumbnail.image"), maxPixelSize: 440)
        precondition(missing == nil)
        print("PASS: background thumbnail decode, sizing, cache and missing image")
    }
}
