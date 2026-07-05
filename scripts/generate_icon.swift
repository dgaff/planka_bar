#!/usr/bin/env swift
// Renders the PlankaBar app icon (same kanban-board glyph as the menu bar
// icon, on a blue rounded-square background) into an .iconset directory.
// Usage: swift scripts/generate_icon.swift <output.iconset>
// Then:  iconutil -c icns <output.iconset> -o Resources/AppIcon.icns

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_icon.swift <output.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Same geometry as StatusIcon.swift, in an 18-unit coordinate space.
func drawGlyph() {
    NSColor.white.setStroke()
    NSColor.white.setFill()

    let board = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 15, height: 14),
                             xRadius: 3.5, yRadius: 3.5)
    board.lineWidth = 1.6
    board.stroke()

    let colWidth: CGFloat = 2.6
    let topY: CGFloat = 12.6
    func column(x: CGFloat, height: CGFloat) {
        let r = NSRect(x: x, y: topY - height, width: colWidth, height: height)
        NSBezierPath(roundedRect: r, xRadius: 1.3, yRadius: 1.3).fill()
    }
    column(x: 4.0, height: 7.4)
    column(x: 7.7, height: 4.6)
    column(x: 11.4, height: 6.2)
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // Apple icon grid: content square ~80% of canvas, corner radius ~22.5%.
    let margin = s * 0.10
    let bg = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: bg.width * 0.225, yRadius: bg.width * 0.225)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.32, green: 0.62, blue: 0.96, alpha: 1),
        ending: NSColor(calibratedRed: 0.09, green: 0.38, blue: 0.80, alpha: 1))!
    gradient.draw(in: bgPath, angle: -90)

    // Map the 18-unit glyph space (centered on 9,9) into ~66% of the background.
    let scale = bg.width * 0.66 / 18.0
    let transform = NSAffineTransform()
    transform.translateX(by: bg.midX - 9 * scale, yBy: bg.midY - 9 * scale)
    transform.scale(by: scale)
    transform.concat()
    drawGlyph()

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    let data = render(pixels: entry.pixels)
    try data.write(to: outDir.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(entries.count) images to \(outDir.path)")
