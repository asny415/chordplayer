import SwiftUI

struct PlayingPatternView: View {
    let pattern: GuitarPattern
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stringCount = 6
            let stepCount = pattern.length
            guard stepCount > 0 else { return }

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

            // Draw beat lines
            let stepsPerBeat = pattern.resolution == .sixteenth ? 4 : 2
            let beatCount = stepCount / stepsPerBeat
            for i in 1..<beatCount {
                let x = CGFloat(i * stepsPerBeat) * stepWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color.opacity(0.5)))
            }

            // Draw events based on the new PatternStep structure
            for (stepIndex, step) in pattern.steps.enumerated() {
                let x = CGFloat(stepIndex) * stepWidth + stepWidth / 2
                
                switch step.type {
                case .rest:
                    break // Draw nothing
                
                case .arpeggio:
                    // Draw a circle for each active note
                    for stringIndex in step.activeNotes {
                        let y = stringSpacing / 2 + CGFloat(stringIndex) * stringSpacing
                        let circlePath = Path(ellipseIn: CGRect(x: x - stringSpacing * 0.2, y: y - stringSpacing * 0.2, width: stringSpacing * 0.4, height: stringSpacing * 0.4))
                        context.fill(circlePath, with: .color(color))
                    }
                
                case .strum:
                    // Draw a single arrow for the whole step
                    let arrowPath = createArrowPath(center: CGPoint(x: x, y: size.height / 2), height: size.height * 0.7, direction: step.strumDirection)
                    context.stroke(arrowPath, with: .color(color), lineWidth: 1.5)
                }
            }
        }
    }

    private func createArrowPath(center: CGPoint, height: CGFloat, direction: StrumDirection) -> Path {
        var path = Path()
        let arrowHeight = height
        let arrowWidth = arrowHeight * 0.4
        
        let yStart = direction == .down ? center.y - arrowHeight / 2 : center.y + arrowHeight / 2
        let yEnd = direction == .down ? center.y + arrowHeight / 2 : center.y - arrowHeight / 2

        path.move(to: CGPoint(x: center.x, y: yStart))
        path.addLine(to: CGPoint(x: center.x, y: yEnd))
        
        path.move(to: CGPoint(x: center.x - arrowWidth / 2, y: yEnd + (direction == .down ? -arrowWidth / 2 : arrowWidth / 2)))
        path.addLine(to: CGPoint(x: center.x, y: yEnd))
        path.addLine(to: CGPoint(x: center.x + arrowWidth / 2, y: yEnd + (direction == .down ? -arrowWidth / 2 : arrowWidth / 2)))
        
        return path
    }
}
