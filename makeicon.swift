import AppKit

let side = 1024
guard CommandLine.arguments.count > 1,
      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("usage: swift makeicon.swift output.png\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = CGFloat(side)
let tile = NSRect(x: 100, y: 100, width: canvas - 200, height: canvas - 200)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.38, green: 0.33, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.94, alpha: 1),
    NSColor(calibratedRed: 0.09, green: 0.74, blue: 0.78, alpha: 1),
])
gradient?.draw(in: shape, angle: -55)

let gloss = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))?
    .draw(in: gloss, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let size = symbol.size
    let white = NSImage(size: size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let origin = NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2)
    white.draw(in: NSRect(origin: origin, size: size))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
