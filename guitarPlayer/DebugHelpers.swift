
import SwiftUI

// Simple debug helper: prints the global frame of the view it's attached to.
struct FrameLogger: View {
    let name: String
    @State private var lastFrame: CGRect = .zero
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    let f = geo.frame(in: .global)
                    print("[FrameLogger] \(name) onAppear frame=\(f)")
                    lastFrame = f
                }
                .onReceive(Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()) { _ in
                    let f = geo.frame(in: .global)
                    if f != lastFrame {
                        lastFrame = f
                        print("[FrameLogger] \(name) changed frame=\(f)")
                    }
                }
        }
    }
}
