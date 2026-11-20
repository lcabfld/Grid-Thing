//
//  StatusBarController.swift
//  Grid Thing
//
//  The menu bar icon. Drop photos or folders on it to queue them up; click it
//  to open the small window underneath with the thumbnails, save and settings.
//

import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let store: GridStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    init(store: GridStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()

        // Keep the queued-image count next to the icon up to date.
        store.$images
            .receive(on: RunLoop.main)
            .sink { [weak self] images in self?.updateCount(images.count) }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Grid Thing")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.toolTip = "Grid Thing: drop photos here"
        button.target = self
        button.action = #selector(togglePopover(_:))

        // The status item lives in its own little window. NSWindow passes drag
        // events on to its delegate, so this lets photos be dropped on the icon.
        button.window?.registerForDraggedTypes([.fileURL, .tiff, .png])
        button.window?.delegate = self
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView().environmentObject(store))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    private func updateCount(_ count: Int) {
        statusItem.button?.title = count > 0 ? " \(count)" : ""
    }

    // MARK: - Showing the popover

    @objc private func togglePopover(_ sender: Any?) {
        popover.isShown ? popover.performClose(sender) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        // Belt and braces: close when clicking anywhere outside the app.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Dropping on the icon

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        let accepted = store.add(from: sender.draggingPasteboard)
        if accepted {
            showPopover()
        }
        return accepted
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
