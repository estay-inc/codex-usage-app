import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output.png>\n", stderr)
    exit(2)
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create icon drawing context.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
defer { NSGraphicsContext.restoreGraphicsState() }

context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let background = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 210,
    yRadius: 210
)
NSColor(calibratedRed: 0x11 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1).setFill()
background.fill()

func drawArc(radius: CGFloat, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.appendArc(
        withCenter: NSPoint(x: 512, y: 512),
        radius: radius,
        startAngle: 36,
        endAngle: 324,
        clockwise: false
    )
    color.setStroke()
    path.stroke()
}

drawArc(
    radius: 326,
    width: 48,
    color: NSColor(calibratedWhite: 0xF2 / 255, alpha: 1)
)
drawArc(
    radius: 210,
    width: 42,
    color: NSColor(calibratedWhite: 0x9A / 255, alpha: 1)
)

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render app icon.\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
