// SPDX-License-Identifier: MIT
// Copyright (c) 2026 HRNPH

import AppKit

// Draw the application icon with the system earbuds symbol.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("MiBuds.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let side = CGFloat(pixels)
        let bounds = NSRect(
            x: side * 0.035, y: side * 0.035, width: side * 0.93, height: side * 0.93)
        let path = NSBezierPath(roundedRect: bounds, xRadius: side * 0.21, yRadius: side * 0.21)
        NSGradient(
            starting: NSColor(calibratedRed: 0.29, green: 0.44, blue: 0.91, alpha: 1),
            ending: NSColor(calibratedRed: 0.15, green: 0.28, blue: 0.72, alpha: 1))!.draw(
                in: path, angle: -75)
        let symbol = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)!
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .medium))!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white]))!
        symbol.draw(
            in: NSRect(x: side * 0.21, y: side * 0.22, width: side * 0.58, height: side * 0.56))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
