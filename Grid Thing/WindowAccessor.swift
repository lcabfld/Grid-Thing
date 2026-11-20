import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    private let operation: (NSWindow?) -> Void
    
    init(_ operation: @escaping (NSWindow?) -> Void) {
        self.operation = operation
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            operation(view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
} 