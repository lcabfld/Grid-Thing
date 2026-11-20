//
//  ContentView.swift
//  Grid Thing
//
//  Created by Luca Bradfield on 9/11/2024.
//
//  The small window that drops down from the menu bar icon.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct PopoverView: View {
    @EnvironmentObject var store: GridStore
    @State private var isDropTargetActive = false

    var body: some View {
        VStack(spacing: 12) {
            dropZone

            if !store.images.isEmpty {
                HStack {
                    Text(store.images.count == 1 ? "1 photo" : "\(store.images.count) photos")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", action: store.clear)
                        .buttonStyle(.link)
                        .disabled(store.isProcessing)
                }
                .font(.callout)
            }

            if store.isProcessing {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                Button("Choose Output Location", action: store.chooseLocationAndSave)
                    .buttonStyle(.bordered)
                    .disabled(store.images.isEmpty)
            }

            if let saved = store.lastSavedURL {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Saved \(saved.lastPathComponent)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Show", action: store.revealLastSaved)
                        .buttonStyle(.link)
                }
                .font(.callout)
            }

            Divider()

            Toggle("Alphabetical order", isOn: $store.alphabeticalOrder)
                .toggleStyle(.switch)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Lay photos out by filename, left to right, top to bottom")
        }
        .padding(14)
        .frame(width: 260)
        .overlay(alignment: .topTrailing) {
            quitButton
                .padding(4)
        }
    }

    /// Small white circle with an X in the top-right corner. Quits Grid Thing.
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black.opacity(0.6), Color.white)
                .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q")
        .help("Quit Grid Thing")
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargetActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(isDropTargetActive ? Color.accentColor : Color.secondary.opacity(0.5))

            if store.images.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 26))
                    Text("Drop photos or a folder")
                        .font(.callout)
                    Text("or click to choose")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
            } else {
                thumbnailStack
            }
        }
        .frame(height: 150)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargetActive) { providers in
            store.add(from: providers)
        }
        .onTapGesture(perform: openImagePicker)
    }

    /// The last few photos, fanned out on top of each other.
    private var thumbnailStack: some View {
        let shown = Array(store.images.suffix(6))
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                    .rotationEffect(.degrees(Double(index - shown.count / 2) * 4))
                    .offset(y: Double(index) * -1.5)
            }
        }
    }

    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else { return }
            store.add(urls: panel.urls)
        }
    }
}

#Preview {
    PopoverView()
        .environmentObject(GridStore())
}
