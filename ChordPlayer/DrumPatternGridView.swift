
import SwiftUI

struct DrumPatternGridView: View {
    let pattern: DrumPattern
    let timeSignature: String
    let activeColor: Color
    let inactiveColor: Color

    private let grid: [[Bool]]
    private let totalSteps: Int

    private enum DrumInstrument: Int, CaseIterable {
        case kick = 36
        case snare = 38
        case hihat = 42
        
        var color: Color {
            switch self {
            case .kick: return .red
            case .snare: return .yellow
            case .hihat: return .cyan
            }
        }
    }

    init(pattern: DrumPattern, timeSignature: String, activeColor: Color, inactiveColor: Color) {
        self.pattern = pattern
        self.timeSignature = timeSignature
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor

        let (beats, beatType) = MusicTheory.parseTimeSignature(timeSignature)
        self.totalSteps = (beats * 4) / (beatType / 4) // e.g. 4/4 -> 16 steps, 3/4 -> 12 steps

        var gridData = Array(repeating: Array(repeating: false, count: totalSteps), count: DrumInstrument.allCases.count)
        var absoluteTime: Double = 0.0

        for (index, event) in pattern.pattern.enumerated() {
            if let delayFraction = MusicTheory.parseDelay(delayString: event.delay) {
                // For the first event, delay is 0, so absoluteTime remains 0.
                // For subsequent events, add the delay from the previous event.
                if index > 0 { 
                    absoluteTime += delayFraction
                }
                
                let timeStep = Int(round(absoluteTime * Double(totalSteps)))

                if timeStep < totalSteps {
                    for note in event.notes {
                        if let instrument = DrumInstrument(rawValue: note) {
                            let instrumentIndex = DrumInstrument.allCases.firstIndex(of: instrument)!
                            gridData[instrumentIndex][timeStep] = true
                        }
                    }
                }
            }
        }
        self.grid = gridData
    }

    var body: some View {
        Canvas { context, size in
            let stepWidth = size.width / CGFloat(totalSteps)
            let instrumentHeight = size.height / CGFloat(DrumInstrument.allCases.count)

            // Draw grid lines
            // Draw vertical line at x=0
            var initialPath = Path()
            initialPath.move(to: CGPoint(x: 0, y: 0))
            initialPath.addLine(to: CGPoint(x: 0, y: size.height))
            context.stroke(initialPath, with: .color(inactiveColor.opacity(0.2)))

            for i in 1..<totalSteps {
                let x = CGFloat(i) * stepWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(inactiveColor.opacity(0.2)))
            }
            for i in 1..<DrumInstrument.allCases.count {
                let y = CGFloat(i) * instrumentHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(inactiveColor.opacity(0.2)))
            }

            // Draw notes
            for (instIndex, instrumentRow) in grid.enumerated() {
                for (stepIndex, hasNote) in instrumentRow.enumerated() {
                    if hasNote {
                        let x = CGFloat(stepIndex) * stepWidth
                        let y = CGFloat(instIndex) * instrumentHeight
                        let rect = CGRect(x: x, y: y, width: stepWidth, height: instrumentHeight).insetBy(dx: 1, dy: 1)
                        let instrument = DrumInstrument.allCases[instIndex]
                        context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(instrument.color.opacity(0.8)))
                    }
                }
            }
        }
        .border(inactiveColor.opacity(0.5), width: 1)
    }
}
