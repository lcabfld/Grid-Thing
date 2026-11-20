//
//  ContentView.swift
//  Grid Thing
//
//  Created by Luca Bradfield on 9/11/2024.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DroppedImage: Identifiable {
    let id = UUID()
    let url: URL
    let image: NSImage
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var droppedImages: [DroppedImage] = []
    @State private var outputURL: URL?
    @State private var isDropTargetActive = false
    @State private var isProcessing = false
    @State private var showingCompletion = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .frame(width: 200, height: 200)
                    .foregroundColor(isDropTargetActive ? .blue : .gray)
                    .contentShape(Rectangle())
                
                if droppedImages.isEmpty {
                    Text("Drop images here")
                        .foregroundColor(.gray)
                } else {
                    // Stacked thumbnails
                    ZStack {
                        ForEach(Array(droppedImages.suffix(6).enumerated().reversed()), id: \.element.id) { index, droppedImage in
                            Image(nsImage: droppedImage.image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                .rotationEffect(.degrees(Double(index - min(droppedImages.count, 6)/2) * 3))
                                .offset(y: Double(index) * -1)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [.image, .fileURL, .folder], isTargeted: $isDropTargetActive) { providers in
                handleDrop(providers: providers)
            }
            .onTapGesture {
                openImagePicker()
            }
            
            // Controls
            Button("Choose Output Location", action: showSaveDialog)
                .buttonStyle(.bordered)
                .disabled(droppedImages.isEmpty || isProcessing)
            
            // Progress indicator
            if isProcessing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
        .padding(20)
        .frame(width: 240, height: 290)
    }
    
    /// The app's own window. `NSApp.windows.first` is not reliable on current macOS
    /// (it can be a system or panel window), so prefer the key/main window.
    private var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private func processGrid() {
        isProcessing = true
        showingCompletion = false

        // Snapshot state on the main thread before handing off to the background
        let images = droppedImages
        let alphabetical = appState.alphabeticalOrder
        let destination = outputURL

        // Process in background
        DispatchQueue.global(qos: .userInitiated).async {
            createGrid(images: images, alphabetical: alphabetical, outputURL: destination)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                isProcessing = false
                droppedImages.removeAll()
                
                // Show and automatically hide completion message
                withAnimation {
                    showingCompletion = true
                }
                
                // Hide message after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showingCompletion = false
                    }
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                // Files and folders dragged from Finder arrive as file URLs
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    self.addItem(at: url)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Image data with no backing file (e.g. dragged from a browser or Photos)
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    let name = provider.suggestedName ?? UUID().uuidString
                    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
                    DispatchQueue.main.async {
                        self.droppedImages.append(DroppedImage(url: url, image: image))
                    }
                }
            }
        }
        return handled
    }

    /// Adds a single image file, or every image inside a folder.
    private func addItem(at url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            processFolder(url)
        } else if let image = NSImage(contentsOf: url) {
            DispatchQueue.main.async {
                self.droppedImages.append(DroppedImage(url: url, image: image))
            }
        }
    }
    
    private func showSaveDialog() {
        guard let window = hostWindow else { return }

        let dialog = NSSavePanel()
        dialog.message = "Choose where to save your grid"
        dialog.nameFieldLabel = "Grid name:"
        dialog.nameFieldStringValue = "grid.png"
        dialog.allowedContentTypes = [.png]
        dialog.canCreateDirectories = true
        dialog.isExtensionHidden = false
        dialog.showsTagField = false
        
        dialog.beginSheetModal(for: window) { response in
        
            if response == .OK {
                self.outputURL = dialog.url
                // Automatically trigger grid creation
                self.processGrid()
            }
        }
    }
    
    private func createGrid(images: [DroppedImage], alphabetical: Bool, outputURL: URL?) {
        guard let outputURL = outputURL, !images.isEmpty else { return }

        // Remove any duplicate images based on URL, keeping the order they were added
        var seen = Set<String>()
        let uniqueImages = images.filter { seen.insert($0.url.absoluteString).inserted }

        // Sort alphabetically by filename if toggle is on
        let sortedImages = alphabetical ?
            uniqueImages.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending } :
            uniqueImages
        
        let targetHeight: CGFloat = 800  // Base height for all images
        let aspectRatio: CGFloat = 16.0/9.0  // Target aspect ratio
        let margin: CGFloat = 50  // Margin between images and edges
        
        // Scale all images to same height while maintaining aspect ratio
        let scaledImages = sortedImages.map { droppedImage -> (NSImage, CGFloat) in
            let scale = targetHeight / droppedImage.image.size.height
            let scaledWidth = droppedImage.image.size.width * scale
            return (droppedImage.image, scaledWidth)
        }
        
        // Calculate optimal number of rows
        let totalWidth = scaledImages.reduce(0) { $0 + $1.1 }
        let estimatedSingleRowHeight = targetHeight
        let estimatedArea = totalWidth * estimatedSingleRowHeight
        let optimalHeight = sqrt(estimatedArea / aspectRatio)
        let optimalRows = max(1, round(optimalHeight / targetHeight))
        
        // Distribute images into rows
        var rows: [[NSImage]] = Array(repeating: [], count: Int(optimalRows))
        var rowWidths: [CGFloat] = Array(repeating: 0, count: Int(optimalRows))
        
        if alphabetical {
            // Place images horizontally across rows in alphabetical order
            for (index, (image, width)) in scaledImages.enumerated() {
                let rowIndex = index / Int(ceil(Double(scaledImages.count) / Double(optimalRows)))
                if rowIndex < rows.count {
                    rows[rowIndex].append(image)
                    rowWidths[rowIndex] += width + margin
                }
            }
        } else {
            // Place images in shortest row (original behavior)
            for (image, width) in scaledImages {
                let shortestRowIndex = rowWidths.firstIndex(of: rowWidths.min()!)!
                rows[shortestRowIndex].append(image)
                rowWidths[shortestRowIndex] += width + margin
            }
        }
        
        // Calculate final dimensions
        let maxRowWidth = rowWidths.max()! + margin
        let finalWidth = maxRowWidth
        let finalHeight = (targetHeight * CGFloat(optimalRows)) + (margin * (CGFloat(optimalRows) + 1))
        
        // Create bitmap context
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
        ) else { return }
        
        // Create graphics context
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        
        // Clear background to transparent
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: finalWidth, height: finalHeight).fill()
        
        // Draw each row
        for (rowIndex, row) in rows.enumerated() {
            // Calculate total width of this row
            let rowWidth = row.reduce(0) { total, image in
                let scale = targetHeight / image.size.height
                return total + (image.size.width * scale) + margin
            } - margin
            
            // Center the row
            let startX = (finalWidth - rowWidth) / 2
            var xOffset = startX
            let yOffset = finalHeight - (CGFloat(rowIndex + 1) * targetHeight) - (CGFloat(rowIndex + 1) * margin)
            
            for image in row {
                let scale = targetHeight / image.size.height
                let scaledWidth = image.size.width * scale
                
                let rect = NSRect(
                    x: xOffset,
                    y: yOffset,
                    width: scaledWidth,
                    height: targetHeight
                )
                
                image.draw(in: rect)
                xOffset += scaledWidth + margin
            }
        }
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Save the final image
        if let imageData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try imageData.write(to: outputURL)
            } catch {
                print("Error saving image:", error)
            }
        }
    }
    
    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .jpeg, .png]
        
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            for url in panel.urls {
                self.addItem(at: url)
            }
        }
        if let window = hostWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }
    
    private func processFolder(_ url: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            guard ["jpg", "jpeg", "png"].contains(fileURL.pathExtension.lowercased()),
                  let image = NSImage(contentsOf: fileURL)
            else { continue }
            
            DispatchQueue.main.async {
                let droppedImage = DroppedImage(url: fileURL, image: image)
                self.droppedImages.append(droppedImage)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
