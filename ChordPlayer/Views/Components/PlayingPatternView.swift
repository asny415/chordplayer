import SwiftUI

struct PlayingPatternView: View {
    let pattern: GuitarPattern
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard !pattern.patternGrid.isEmpty, !pattern.patternGrid[0].isEmpty else { return }
            
            let stringCount = pattern.strings
            let stepCount = pattern.steps
            
            let stepWidth = size.width / CGFloat(stepCount)
            let stringSpacing = size.height / CGFloat(stringCount)

            // Draw string lines
            for i in 0..<stringCount {
                let y = stringSpacing / 2 + CGFloat(i) * stringSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color.opacity(0.3)))
            }
            
            // Draw beat lines (assuming 4 beats for now)
            // TODO: Use time signature from preset for accurate beat lines
            let beats = 4
            let stepsPerBeat = stepCount / beats
            for i in 1..<beats {
                let x = CGFloat(i * stepsPerBeat) * stepWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color.opacity(0.5)))
            }

            // Draw events (notes)
            for (stringIndex, stringRow) in pattern.patternGrid.enumerated() {
                for (stepIndex, hasNote) in stringRow.enumerated() {
                    if hasNote {
                        let x = CGFloat(stepIndex) * stepWidth + stepWidth / 2
                        let y = stringSpacing / 2 + CGFloat(stringIndex) * stringSpacing
                        let pick = createPickPath(center: CGPoint(x: x, y: y), size: stringSpacing * 0.8)
                        context.fill(pick, with: .color(color))
                    }
                }
            }
        }
    }

    private func createPickPath(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        let width = size
        let height = size
        let topPoint = CGPoint(x: center.x, y: center.y - height / 2)
        let leftPoint = CGPoint(x: center.x - width / 2, y: center.y)
        let rightPoint = CGPoint(x: center.x + width / 2, y: center.y)
        let bottomPoint = CGPoint(x: center.x, y: center.y + height / 2)

        path.move(to: topPoint)
        path.addQuadCurve(to: leftPoint, control: CGPoint(x: center.x - width * 0.4, y: center.y - height * 0.4))
        path.addQuadCurve(to: bottomPoint, control: CGPoint(x: center.x - width * 0.1, y: center.y + height * 0.4))
        path.addQuadCurve(to: rightPoint, control: CGPoint(x: center.x + width * 0.1, y: center.y + height * 0.4))
        path.addQuadCurve(to: topPoint, control: CGPoint(x: center.x + width * 0.4, y: center.y - height * 0.4))
        path.closeSubpath()
        return path
    }
}