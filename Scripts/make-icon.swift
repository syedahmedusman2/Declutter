import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func draw(size: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.62, alpha: 1).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.18, yRadius: size * 0.18).fill()
    NSColor.white.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: size * 0.50, y: size * 0.74))
    shaft.line(to: NSPoint(x: size * 0.50, y: size * 0.34))
    shaft.lineWidth = size * 0.07
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: size * 0.34, y: size * 0.46))
    head.line(to: NSPoint(x: size * 0.50, y: size * 0.26))
    head.line(to: NSPoint(x: size * 0.66, y: size * 0.46))
    head.lineWidth = size * 0.07
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode icon")
    }
    return png
}

for size in sizes {
    let data = draw(size: CGFloat(size))
    try data.write(to: root.appendingPathComponent("icon_\(size).png"))
}
