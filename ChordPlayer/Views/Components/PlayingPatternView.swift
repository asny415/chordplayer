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
            let stepsPerBeat = pattern.activeResolution.stepsPerBeat
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
                    // Draw a circle for each active note, sorted for consistent display
                    for stringIndex in step.activeNotes.sorted() {
                        let y = stringSpacing / 2 + CGFloat(stringIndex) * stringSpacing
                        let circlePath = Path(ellipseIn: CGRect(x: x - stringSpacing * 0.2, y: y - stringSpacing * 0.2, width: stringSpacing * 0.4, height: stringSpacing * 0.4))
                        context.fill(circlePath, with: .color(color))
                    }
                
                case .strum:
                    guard let minStringIndex = step.activeNotes.min(),
                          let maxStringIndex = step.activeNotes.max() else {
                        break
                    }

                    let topStringY = stringSpacing / 2 + CGFloat(minStringIndex) * stringSpacing
                    let bottomStringY = stringSpacing / 2 + CGFloat(maxStringIndex) * stringSpacing

                    // If only one string is strummed, we still want a small visual indicator.
                    // We'll center the arrow on the string and give it a small height.
                    let isSingleStringStrum = minStringIndex == maxStringIndex
                    
                    let arrowCenterY = (topStringY + bottomStringY) / 2
                    // Ensure there's a minimum height for the arrow, especially for single-string "strums".
                    let arrowHeight = isSingleStringStrum ? stringSpacing * 0.4 : bottomStringY - topStringY

                    let arrowPath = createArrowPath(
                        center: CGPoint(x: x, y: arrowCenterY),
                        height: arrowHeight,
                        direction: step.strumDirection,
                        speed: step.strumSpeed,
                        stringSpacing: stringSpacing
                    )
                    context.stroke(arrowPath, with: .color(color), lineWidth: 1.5)
                }
            }
        }
    }

    private func createArrowPath(center: CGPoint, height: CGFloat, direction: StrumDirection, speed: StrumSpeed, stringSpacing: CGFloat) -> Path {
        var path = Path()
        let arrowHeight = height
        // Make arrow width consistent and based on string spacing, not variable height
        let arrowWidth = stringSpacing * 0.6
        
        let startPoint = CGPoint(x: center.x, y: direction == .down ? center.y - arrowHeight / 2 : center.y + arrowHeight / 2)
        let endPoint = CGPoint(x: center.x, y: direction == .down ? center.y + arrowHeight / 2 : center.y - arrowHeight / 2)

        path.move(to: startPoint)

        if speed == .slow {
            // Draw a wavy line with a fixed frequency
            let waveCycleLength: CGFloat = 8.0 // The vertical length of one full wave cycle
            let totalVerticalDistance = abs(endPoint.y - startPoint.y)
            
            // A full cycle has two segments (one left, one right). Calculate how many segments fit.
            let segmentCount = max(2, Int(totalVerticalDistance / (waveCycleLength / 2.0)))
            let segmentHeight = (endPoint.y - startPoint.y) / CGFloat(segmentCount)
            let waveAmplitude = arrowWidth * 0.3

            var currentPoint = startPoint
            for i in 1...segmentCount {
                let nextPoint = CGPoint(x: startPoint.x, y: startPoint.y + CGFloat(i) * segmentHeight)
                
                // Alternate the control point side for each segment
                let controlPointX = startPoint.x + ((i % 2 == 0) ? waveAmplitude : -waveAmplitude)
                let controlPointY = currentPoint.y + segmentHeight / 2
                let controlPoint = CGPoint(x: controlPointX, y: controlPointY)
                
                path.addQuadCurve(to: nextPoint, control: controlPoint)
                currentPoint = nextPoint
            }
        } else {
            // Draw a straight line for medium/fast strums
            path.addLine(to: endPoint)
        }
        
        // Draw arrowhead
        let yEnd = endPoint.y
        let arrowheadSize = arrowWidth * 0.5 // The length of the arrowhead's "wings"
        path.move(to: CGPoint(x: center.x - arrowheadSize, y: yEnd + (direction == .down ? -arrowheadSize : arrowheadSize)))
        path.addLine(to: CGPoint(x: center.x, y: yEnd))
        path.addLine(to: CGPoint(x: center.x + arrowheadSize, y: yEnd + (direction == .down ? -arrowheadSize : arrowheadSize)))
        
        return path
    }
}
