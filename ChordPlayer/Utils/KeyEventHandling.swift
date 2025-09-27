
import SwiftUI

// MARK: - KeyDown Handling Utility

/**
 This extension provides a convenient way to handle key down events on any SwiftUI View.
 It uses a NSViewRepresentable wrapper around a custom NSView to capture keyboard input.
*/

extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        self.background(KeyEventHandlingView(onKeyDown: action))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyDownView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 尝试设置为第一响应者以接收键盘事件
        DispatchQueue.main.async {
            if nsView.window != nil {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyDownView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // If the handler consumes the event (returns true), don't pass it up the responder chain.
        if let handler = onKeyDown, handler(event) {
            return
        }
        // Otherwise, allow the default behavior.
        super.keyDown(with: event)
    }
}
