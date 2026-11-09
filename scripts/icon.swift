// Draws TaskDock's app icon (the menu bar's ◎ scope on TaskDock blue) into Resources/AppIcon.icns.
// Usage: swift scripts/icon.swift   (needs iconutil, part of macOS)
import AppKit

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // Apple's icon grid: the shape fills 824 of 1024 points, centered.
    let box = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)
    NSGradient(starting: NSColor(red: 0.27, green: 0.52, blue: 1, alpha: 1),
               ending: NSColor(red: 0.12, green: 0.32, blue: 0.86, alpha: 1))!.draw(in: shape, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: box.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for pt in [16, 32, 128, 256, 512] {
    try draw(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try draw(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
