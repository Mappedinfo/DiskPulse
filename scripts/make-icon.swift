import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.35, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 210, yRadius: 210).fill()
        let ring = NSBezierPath(ovalIn: NSRect(x: 242, y: 242, width: 540, height: 540))
        ring.lineWidth = 56
        NSColor.white.withAlphaComponent(0.2).setStroke()
        ring.stroke()
        let fill = NSBezierPath()
        fill.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 270, startAngle: 90, endAngle: -162, clockwise: true)
        fill.lineWidth = 56
        fill.lineCapStyle = .round
        NSColor(calibratedRed: 0.78, green: 0.96, blue: 0.84, alpha: 1).setStroke()
        fill.stroke()
        let pulse = NSBezierPath()
        pulse.move(to: NSPoint(x: 346, y: 500))
        for point in [NSPoint(x: 440, y: 500), NSPoint(x: 485, y: 600), NSPoint(x: 548, y: 421), NSPoint(x: 596, y: 500), NSPoint(x: 675, y: 500)] { pulse.line(to: point) }
        pulse.lineWidth = 30
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        NSColor.white.setStroke()
        pulse.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let output = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
}
