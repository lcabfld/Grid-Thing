//
//  GridRenderer.swift
//  Grid Thing
//
//  Lays images out in rows of equal height, aiming for a 16:9 sheet,
//  and renders them to a transparent PNG.
//

import AppKit

enum GridRenderer {
    static let targetHeight: CGFloat = 800  // Base height for all images
    static let aspectRatio: CGFloat = 16.0 / 9.0  // Target aspect ratio
    static let margin: CGFloat = 50  // Margin between images and edges

    static func render(_ images: [DroppedImage], alphabetical: Bool) -> Data? {
        // Remove any duplicate images based on URL, keeping the order they were added
        var seen = Set<String>()
        let uniqueImages = images.filter { seen.insert($0.url.absoluteString).inserted && $0.image.size.height > 0 }
        guard !uniqueImages.isEmpty else { return nil }

        // Sort alphabetically by filename if the setting is on
        let sortedImages = alphabetical
            ? uniqueImages.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            : uniqueImages

        // Scale all images to same height while maintaining aspect ratio
        let scaledImages = sortedImages.map { droppedImage -> (NSImage, CGFloat) in
            let scale = targetHeight / droppedImage.image.size.height
            return (droppedImage.image, droppedImage.image.size.width * scale)
        }

        // Calculate optimal number of rows
        let totalWidth = scaledImages.reduce(0) { $0 + $1.1 }
        let estimatedArea = totalWidth * targetHeight
        let optimalHeight = sqrt(estimatedArea / aspectRatio)
        let rowCount = Int(max(1, min(CGFloat(scaledImages.count), round(optimalHeight / targetHeight))))

        // Distribute images into rows
        var rows: [[(NSImage, CGFloat)]] = Array(repeating: [], count: rowCount)
        var rowWidths: [CGFloat] = Array(repeating: 0, count: rowCount)

        if alphabetical {
            // Fill rows left to right, top to bottom, in alphabetical order
            let perRow = Int(ceil(Double(scaledImages.count) / Double(rowCount)))
            for (index, item) in scaledImages.enumerated() {
                let rowIndex = min(index / perRow, rowCount - 1)
                rows[rowIndex].append(item)
                rowWidths[rowIndex] += item.1 + margin
            }
        } else {
            // Place each image in the currently shortest row
            for item in scaledImages {
                let shortest = rowWidths.indices.min { rowWidths[$0] < rowWidths[$1] }!
                rows[shortest].append(item)
                rowWidths[shortest] += item.1 + margin
            }
        }

        // Calculate final dimensions
        let finalWidth = (rowWidths.max() ?? 0) + margin
        let finalHeight = (targetHeight * CGFloat(rowCount)) + (margin * CGFloat(rowCount + 1))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(finalWidth),
            pixelsHigh: Int(finalHeight),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // Clear background to transparent
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: finalWidth, height: finalHeight).fill()

        // Draw each row, centred
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.reduce(0) { $0 + $1.1 + margin } - margin
            var xOffset = (finalWidth - rowWidth) / 2
            let yOffset = finalHeight - (CGFloat(rowIndex + 1) * (targetHeight + margin))

            for (image, width) in row {
                image.draw(in: NSRect(x: xOffset, y: yOffset, width: width, height: targetHeight))
                xOffset += width + margin
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
