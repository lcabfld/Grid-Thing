//
//  Grid_ThingApp.swift
//  Grid Thing
//
//  Created by Luca Bradfield on 9/11/2024.
//
//  Grid Thing runs from the menu bar only: no Dock icon and no main window.
//

import SwiftUI

@main
struct Grid_ThingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Everything lives in the menu bar popover; this scene is never shown.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = GridStore()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController(store: store)
    }
}
