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
            guard instrumentCount > 0 else { return }
            let stepCount = pattern.length
            
            let stepWidth = size.width / CGFloat(stepCount)
            let ySpacing = size.height / CGFloat(instrumentCount)

            // Draw notes as pips/dots
            for (instIndex, instrumentRow) in pattern.patternGrid.enumerated() {
                for (stepIndex, hasNote) in instrumentRow.enumerated() {
                    if hasNote {
                        let x = CGFloat(stepIndex) * stepWidth
                        // Center the 'pip' vertically in the instrument's allotted space
                        let y = (CGFloat(instIndex) + 0.5) * ySpacing
                        let rect = CGRect(x: x, y: y - 1.5, width: max(1, stepWidth - 1), height: 3)
                        let instrumentColor = colorForInstrument(at: instIndex)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(instrumentColor))
                    }
                }
            }
        }
    }
}