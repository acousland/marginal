import AppKit

let folder = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = AffineTransform(scale: factor)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205).fill()
        NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 232, y: 190, width: 560, height: 650), xRadius: 32, yRadius: 32).fill()
        NSColor(calibratedRed: 0.85, green: 0.38, blue: 0.27, alpha: 1).setStroke()
        let margin = NSBezierPath()
        margin.lineWidth = 10
        margin.move(to: NSPoint(x: 324, y: 228)); margin.line(to: NSPoint(x: 324, y: 802)); margin.stroke()
        NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.23, alpha: 1).setStroke()
        let m = NSBezierPath()
        m.lineWidth = 43; m.lineCapStyle = .round; m.lineJoinStyle = .round
        m.move(to: NSPoint(x: 407, y: 493)); m.line(to: NSPoint(x: 407, y: 669)); m.line(to: NSPoint(x: 512, y: 540)); m.line(to: NSPoint(x: 617, y: 669)); m.line(to: NSPoint(x: 617, y: 493)); m.stroke()
        NSColor(calibratedRed: 0.64, green: 0.66, blue: 0.63, alpha: 1).setStroke()
        for (y, width) in [(410.0, 261.0), (348.0, 210.0)] {
            let line = NSBezierPath(); line.lineWidth = 17; line.lineCapStyle = .round
            line.move(to: NSPoint(x: 407, y: y)); line.line(to: NSPoint(x: 407 + width, y: y)); line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
