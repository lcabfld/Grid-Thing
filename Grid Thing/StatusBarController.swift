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

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let store: GridStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var dropView: StatusItemDropView?
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
        button.image = MenuBarIcon.image
        button.imagePosition = .imageLeading
        button.toolTip = "Grid Thing: drop photos here"
        // Kept for keyboard and VoiceOver; mouse clicks go through the drop view below.
        button.target = self
        button.action = #selector(togglePopover(_:))

        // A transparent view laid over the icon that accepts dropped files.
        let dropView = StatusItemDropView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onClick = { [weak self] in self?.togglePopover(nil) }
        dropView.onRightClick = { [weak self] in self?.showContextMenu() }
        dropView.onDragHighlight = { [weak button] on in button?.highlight(on) }
        dropView.onDrop = { [weak self] pasteboard in self?.handleDrop(pasteboard) ?? false }
        button.addSubview(dropView)
        self.dropView = dropView
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
        statusItem.button?.highlight(true)
        // Close when clicking anywhere outside the app.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Right-click menu

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Grid Thing", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Attach the menu just for this click so it drops down from the icon like a
        // normal menu bar menu, then detach it so left-clicks still open the window.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Dropping on the icon

    private func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        let accepted = store.add(from: pasteboard)
        if accepted {
            showPopover()
        }
        return accepted
    }
}

/// Sits on top of the status bar button: takes the drag-and-drop, and passes clicks on.
final class StatusItemDropView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var onDragHighlight: ((Bool) -> Void)?

    private static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .tiff,
        .png,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.image"),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        // Control-click counts as a right-click, as everywhere else on the Mac.
        if event.modifierFlags.contains(.control) {
            onRightClick?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }
        onDragHighlight?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragHighlight?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragHighlight?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragHighlight?(false)
        return onDrop?(sender.draggingPasteboard) ?? false
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }
}
