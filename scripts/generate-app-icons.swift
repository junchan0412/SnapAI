import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func render(dark: Bool, pixels: Int, destination: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.35 : 0.18)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    rounded(NSRect(x: 72, y: 72, width: 880, height: 880), 202, color(dark ? 0x1C2424 : 0xF3F5EF))
    shadow.shadowColor = .clear
    shadow.set()
    let border = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 200, yRadius: 200)
    NSColor.white.withAlphaComponent(dark ? 0.14 : 0.85).setStroke()
    border.lineWidth = 3
    border.stroke()
    rounded(NSRect(x: 244, y: 264, width: 530, height: 512), 115, color(dark ? 0x33564E : 0xCCE2D7))
    rounded(NSRect(x: 206, y: 230, width: 530, height: 512), 115, color(dark ? 0xBCE7D5 : 0x185C4A))
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 272, y: 285))
    tail.line(to: NSPoint(x: 272, y: 170))
    tail.line(to: NSPoint(x: 415, y: 270))
    tail.close()
    color(dark ? 0xBCE7D5 : 0x185C4A).setFill()
    tail.fill()
    let ink = color(dark ? 0x173B31 : 0xF5F8EE)
    let textWeight = max(40, 1024 / CGFloat(pixels))
    rounded(NSRect(x: 302, y: 541, width: 194, height: textWeight), textWeight / 2, ink)
    rounded(NSRect(x: 302, y: 446, width: 126, height: textWeight), textWeight / 2, ink)
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 588, y: 625))
    cursor.line(to: NSPoint(x: 588, y: 394))
    cursor.move(to: NSPoint(x: 546, y: 625))
    cursor.line(to: NSPoint(x: 630, y: 625))
    cursor.move(to: NSPoint(x: 546, y: 394))
    cursor.line(to: NSPoint(x: 630, y: 394))
    ink.setStroke()
    cursor.lineWidth = textWeight
    cursor.lineCapStyle = .round
    cursor.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}
for dark in [false, true] {
    let name = dark ? "AppIconDark" : "AppIconLight"
    try render(dark: dark, pixels: 1024, destination: root.appendingPathComponent(name + ".png"))
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for size in [16, 32, 128, 256, 512] {
        try render(dark: dark, pixels: size, destination: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try render(dark: dark, pixels: size * 2, destination: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent(name + ".icns").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
}
