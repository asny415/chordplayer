
import SwiftUI

struct PlayheadView: View {
    var body: some View {
        // Use .topLeading alignment and precise offsets to align the shapes
        ZStack(alignment: .topLeading) {
            // The main vertical line of the playhead
            Rectangle()
                .fill(Color.red)
                .frame(width: 1.5)
                // Offset by half its width to center it on the ZStack's leading edge
                .offset(x: -0.75)

            // The "fancy" triangle at the top
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 12, y: 0))
                path.addLine(to: CGPoint(x: 6, y: 12))
                path.closeSubpath()
            }
            .fill(Color.red)
            .frame(width: 12, height: 12)
            // Offset by half the triangle's width to center its tip on the ZStack's leading edge
            .offset(x: -6)
        }
    }
}
