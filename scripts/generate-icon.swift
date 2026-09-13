// Editable vector construction for the ClipNest application icon.
import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let base = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
        NSColor(srgbRed: 0.12, green: 0.18, blue: 0.30, alpha: 1).setFill()
        base.fill()
        NSColor(srgbRed: 0.35, green: 0.74, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 272, y: 235, width: 490, height: 540), xRadius: 66, yRadius: 66).fill()
        NSColor(srgbRed: 0.92, green: 0.96, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 218, y: 290, width: 490, height: 540), xRadius: 66, yRadius: 66).fill()
        NSColor(srgbRed: 0.12, green: 0.18, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 354, y: 778, width: 220, height: 82), xRadius: 35, yRadius: 35).fill()
        let nest = NSBezierPath()
        nest.move(to: NSPoint(x: 321, y: 565))
        nest.curve(to: NSPoint(x: 606, y: 565), controlPoint1: NSPoint(x: 370, y: 424), controlPoint2: NSPoint(x: 557, y: 424))
        nest.lineWidth = 44
        nest.lineCapStyle = .round
        NSColor(srgbRed: 0.19, green: 0.50, blue: 0.51, alpha: 1).setStroke()
        nest.stroke()
        let lower = NSBezierPath()
        lower.move(to: NSPoint(x: 352, y: 439))
        lower.curve(to: NSPoint(x: 575, y: 439), controlPoint1: NSPoint(x: 418, y: 370), controlPoint2: NSPoint(x: 509, y: 370))
        lower.lineWidth = 35
        lower.lineCapStyle = .round
        lower.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
