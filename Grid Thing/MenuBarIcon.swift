//
//  MenuBarIcon.swift
//  Grid Thing
//
//  The pixel "Gt" from the app icon, redrawn as a crisp menu bar template image.
//

import AppKit

enum MenuBarIcon {
    /// The Gt glyph, sampled pixel-for-pixel from the app icon (11 × 8).
    private static let glyph = [
        ".###...#...",
        "#...#..#...",
        "#.....#####",
        "#......#...",
        "#..##..#...",
        "#...#..#...",
        "#...#..#..#",
        ".###....##.",
    ]

    /// Points per glyph pixel. 1.5pt is exactly 3 Retina pixels, so every stroke
    /// stays sharp and even (an exact 30% shrink, 1.4pt, gives uneven 2px/3px strokes).
    private static let unit: CGFloat = 1.5

    static let image: NSImage = {
        let rows = glyph.count
        let columns = glyph[0].count
        let size = NSSize(width: CGFloat(columns) * unit, height: CGFloat(rows) * unit)

        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (row, line) in glyph.enumerated() {
                for (column, character) in line.enumerated() where character == "#" {
                    NSRect(x: CGFloat(column) * unit, y: CGFloat(row) * unit, width: unit, height: unit).fill()
                }
            }
            return true
        }
        // Template images are tinted by the system for light/dark menu bars.
        image.isTemplate = true
        image.accessibilityDescription = "Grid Thing"
        return image
    }()
}
