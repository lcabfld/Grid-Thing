//
//  Grid_ThingApp.swift
//  Grid Thing
//
//  Created by Luca Bradfield on 9/11/2024.
//

import SwiftUI

@main
struct Grid_ThingApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button(appState.alphabeticalOrder ? "Turn Off Alphabetical Order" : "Turn On Alphabetical Order") {
                    appState.alphabeticalOrder.toggle()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var alphabeticalOrder = false
}
