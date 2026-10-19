// Draws the app icon and writes Resources/AppIcon.icns.
//
// Run:  swift tools/make_icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: an 824pt rounded square centred in 1024.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSShadow().apply { $0.shadowColor = .black.withAlphaComponent(0.3); $0.shadowBlurRadius = 20 * s; $0.shadowOffset = NSSize(width: 0, height: -8 * s) }
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.13, green: 0.25, blue: 0.75, alpha: 1))!
        .draw(in: path, angle: -90)
    NSShadow().set()

    // A key cap in the middle.
    let key = NSRect(x: 232 * s, y: 250 * s, width: 560 * s, height: 524 * s)
    let keyPath = NSBezierPath(roundedRect: key, xRadius: 90 * s, yRadius: 90 * s)
    NSColor.white.withAlphaComponent(0.96).setFill()
    keyPath.fill()

    func draw(_ text: String, at point: NSPoint, size fontSize: CGFloat, color: NSColor) {
        let font = NSFont.systemFont(ofSize: fontSize * s, weight: .semibold)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let b = str.size()
        str.draw(at: NSPoint(x: point.x * s - b.width / 2, y: point.y * s - b.height / 2))
    }
    let blue = NSColor(calibratedRed: 0.15, green: 0.33, blue: 0.85, alpha: 1)
    draw("א", at: NSPoint(x: 400, y: 580), size: 230, color: blue)
    draw("A", at: NSPoint(x: 625, y: 430), size: 230, color: .darkGray)

    // Swap arrows.
    let arrows = NSAttributedString(string: "⇄", attributes: [
        .font: NSFont.systemFont(ofSize: 120 * s, weight: .bold),
        .foregroundColor: NSColor.white])
    let ab = arrows.size()
    let badge = NSRect(x: 640 * s, y: 600 * s, width: 210 * s, height: 210 * s)
    NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.1, alpha: 1).setFill()
    NSBezierPath(ovalIn: badge).fill()
    arrows.draw(at: NSPoint(x: badge.midX - ab.width / 2, y: badge.midY - ab.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSShadow { func apply(_ f: (NSShadow) -> Void) { f(self); set() } }

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
try! render(size: 512).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-preview.png"))
print("Wrote Resources/AppIcon.icns")
