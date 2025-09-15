import SwiftUI

struct DrumPatternGridView: View {
    let pattern: DrumPattern
    let activeColor: Color
    let inactiveColor: Color

    // A simple color mapping for instruments.
    private func colorForInstrument(at index: Int) -> Color {
        let colors: [Color] = [.red, .yellow, .cyan, .green, .orange, .purple]
        return colors[index % colors.count]
    }

    var body: some View {
        Canvas { context, size in
            guard !pattern.patternGrid.isEmpty, !pattern.patternGrid[0].isEmpty else { return }
            
            let instrumentCount = pattern.instruments.count
            let stepCount = pattern.steps
            
            let stepWidth = size.width / CGFloat(stepCount)
            let instrumentHeight = size.height / CGFloat(instrumentCount)

            // Draw grid lines
            for i in 1..<stepCount {
                let x = CGFloat(i) * stepWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(inactiveColor.opacity(0.2)))
            }
            for i in 1..<instrumentCount {
                let y = CGFloat(i) * instrumentHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(inactiveColor.opacity(0.2)))
            }

            // Draw notes
            for (instIndex, instrumentRow) in pattern.patternGrid.enumerated() {
                for (stepIndex, hasNote) in instrumentRow.enumerated() {
                    if hasNote {
                        let x = CGFloat(stepIndex) * stepWidth
                        let y = CGFloat(instIndex) * instrumentHeight
                        let rect = CGRect(x: x, y: y, width: stepWidth, height: instrumentHeight).insetBy(dx: 1, dy: 1)
                        let instrumentColor = colorForInstrument(at: instIndex)
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(instrumentColor.opacity(0.8)))
                    }
                }
            }
        }
        .border(inactiveColor.opacity(0.5), width: 1)
    }
}