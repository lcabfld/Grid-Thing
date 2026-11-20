//
//  GridStore.swift
//  Grid Thing
//
//  Shared state for the menu bar icon and the popover: the queued images,
//  the settings, and saving the finished grid.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DroppedImage: Identifiable {
    let id = UUID()
    let url: URL
    let image: NSImage
}

final class GridStore: ObservableObject {
    @Published private(set) var images: [DroppedImage] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var lastSavedURL: URL?
    @Published var alphabeticalOrder: Bool {
        didSet { UserDefaults.standard.set(alphabeticalOrder, forKey: Self.alphabeticalKey) }
    }

    private static let alphabeticalKey = "alphabeticalOrder"
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    init() {
        alphabeticalOrder = UserDefaults.standard.bool(forKey: Self.alphabeticalKey)
    }

    // MARK: - Adding images

    /// Adds image files, and every image inside any folders, skipping ones already queued.
    func add(urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [DroppedImage] = []
            for url in urls {
                for fileURL in Self.imageFiles(at: url) {
                    if let image = NSImage(contentsOf: fileURL) {
                        found.append(DroppedImage(url: fileURL, image: image))
                    }
                }
            }
            DispatchQueue.main.async { self.append(found) }
        }
    }

    /// Adds an image that has no file behind it (e.g. dragged out of a browser).
    func add(image: NSImage, suggestedName: String?) {
        let name = suggestedName ?? UUID().uuidString
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)-\(name)")
        append([DroppedImage(url: url, image: image)])
    }

    /// Reads whatever was dropped on the menu bar icon.
    @discardableResult
    func add(from pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            add(urls: urls)
            return true
        }
        if let pasted = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage], !pasted.isEmpty {
            pasted.forEach { add(image: $0, suggestedName: nil) }
            return true
        }
        return false
    }

    /// Reads whatever was dropped on the popover's drop zone.
    func add(from providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL else { return }
                    DispatchQueue.main.async { self.add(urls: [url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self.add(image: image, suggestedName: provider.suggestedName) }
                }
            }
        }
        return handled
    }

    func clear() {
        images.removeAll()
        lastSavedURL = nil
    }

    private func append(_ new: [DroppedImage]) {
        let existing = Set(images.map(\.url))
        let fresh = new.filter { !existing.contains($0.url) }
        guard !fresh.isEmpty else { return }
        lastSavedURL = nil
        images.append(contentsOf: fresh)
    }

    /// The image files at a URL: the file itself, or every image inside a folder.
    static func imageFiles(at url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            return isImageFile(url) ? [url] : []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        if imageExtensions.contains(url.pathExtension.lowercased()) { return true }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) ?? false
    }

    // MARK: - Saving

    /// Asks where to save, then renders and writes the grid.
    func chooseLocationAndSave() {
        guard !images.isEmpty, !isProcessing else { return }

        // A menu bar app has to bring itself forward for the panel to get focus.
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.message = "Choose where to save your grid"
        panel.nameFieldLabel = "Grid name:"
        panel.nameFieldStringValue = "grid.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.showsTagField = false
        panel.level = .floating

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.save(to: url)
        }
    }

    private func save(to url: URL) {
        isProcessing = true
        let snapshot = images
        let alphabetical = alphabeticalOrder

        DispatchQueue.global(qos: .userInitiated).async {
            let data = GridRenderer.render(snapshot, alphabetical: alphabetical)
            var saved = false
            if let data {
                do {
                    try data.write(to: url)
                    saved = true
                } catch {
                    NSLog("Grid Thing: error saving grid: \(error)")
                }
            }
            DispatchQueue.main.async {
                self.isProcessing = false
                if saved {
                    self.images.removeAll()
                    self.lastSavedURL = url
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    func revealLastSaved() {
        guard let url = lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
