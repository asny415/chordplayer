
import SwiftUI

struct PlayingPatternView: View {
    let pattern: GuitarPattern
    let timeSignature: String
    let color: Color

    private let events: [PatternDisplayEvent]
    private let totalSteps: Int

    private enum EventType {
        case single(string: Int)
        case strum(direction: StrumDirection, fromString: Int, toString: Int)
    }

    private enum StrumDirection {
        case down, up
    }

    private struct PatternDisplayEvent {
        let timeStep: Int
        let type: EventType
    }

    init(pattern: GuitarPattern, timeSignature: String, color: Color) {
        self.pattern = pattern
        self.timeSignature = timeSignature
        self.color = color

        let (beats, beatType) = MusicTheory.parseTimeSignature(timeSignature)
        self.totalSteps = (beats * 16) / beatType // 4/4 -> 16, 3/4 -> 12

        var parsedEvents: [PatternDisplayEvent] = []
        for event in pattern.pattern {
            guard let delayFraction = MusicTheory.parsePatternDelay(event.delay) else { continue }

            let measureDuration = Double(beats) / Double(beatType)
            let relativePosition = measureDuration > 0 ? delayFraction / measureDuration : 0
            let timeStep = Int(round(relativePosition * Double(totalSteps)))

            let stringNotes = event.notes.compactMap { note -> Int? in
                switch note {
                case .chordString(let stringNum):
                    if (1...6).contains(stringNum) { return stringNum } // 1-6
                case .chordRoot(let s):
                    if s == "ROOT" {
                        return 5
                    } else if s.hasPrefix("ROOT-"), let nStr = s.split(separator: "-").last, let n = Int(nStr) {
                        let stringNum = 5 - n
                        if (1...6).contains(stringNum) {
                            return stringNum
                        }
                    }
                case .specificFret(let string, _):
                    if (1...6).contains(string) { return string }
                }
                return nil
            }

            let isStrum = (event.delta ?? 0) > 0 && stringNotes.count > 1

            if isStrum, let fromString = stringNotes.first, let toString = stringNotes.last {
                let direction: StrumDirection = fromString > toString ? .down : .up
                parsedEvents.append(PatternDisplayEvent(timeStep: timeStep, type: .strum(direction: direction, fromString: fromString, toString: toString)))
            } else { // Treat as single notes
                for note in stringNotes {
                    parsedEvents.append(PatternDisplayEvent(timeStep: timeStep, type: .single(string: note)))
                }
            }
        }
        self.events = parsedEvents
    }

    var body: some View {
        Canvas { context, size in
            let stepWidth = size.width / CGFloat(totalSteps)
            let stringSpacing = size.height / 6.0

            // Draw string lines
            for i in 0..<6 {
                let y = stringSpacing / 2 + CGFloat(i) * stringSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(color.opacity(0.3)))
            }
            
            // Draw beat lines
            let (beats, _) = MusicTheory.parseTimeSignature(timeSignature)
            let stepsPerBeat = totalSteps / beats
            for i in 1..<beats {
                let x = CGFloat(i * stepsPerBeat) * stepWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(color.opacity(0.5)))
            }

            // Draw events
            for event in events {
                let x = CGFloat(event.timeStep) * stepWidth + stepWidth / 2
                switch event.type {
                case .single(let stringNum):
                    let y = stringSpacing / 2 + CGFloat(stringNum - 1) * stringSpacing
                    let pick = createPickPath(center: CGPoint(x: x, y: y), size: stringSpacing * 0.8)
                    context.fill(pick, with: .color(color))
                case .strum(let direction, let fromString, let toString):
                    let arrowPath = createStrumArrow(direction: direction, x: x, fromString: fromString, toString: toString, stringSpacing: stringSpacing)
                    context.stroke(arrowPath, with: .color(color), lineWidth: 1.5)
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
    
    private func createStrumArrow(direction: StrumDirection, x: CGFloat, fromString: Int, toString: Int, stringSpacing: CGFloat) -> Path {
        var path = Path()
        let y1 = stringSpacing / 2 + CGFloat(fromString - 1) * stringSpacing
        let y2 = stringSpacing / 2 + CGFloat(toString - 1) * stringSpacing
        let arrowSize = stringSpacing * 0.4

        if direction == .down { // physical up-strum, arrow points up
            let startY = max(y1, y2)
            let endY = min(y1, y2)
            path.move(to: CGPoint(x: x, y: startY))
            path.addLine(to: CGPoint(x: x, y: endY))
            path.move(to: CGPoint(x: x - arrowSize, y: endY + arrowSize))
            path.addLine(to: CGPoint(x: x, y: endY))
            path.addLine(to: CGPoint(x: x + arrowSize, y: endY + arrowSize))
        } else { // .up, physical down-strum, arrow points down
            let startY = min(y1, y2)
            let endY = max(y1, y2)
            path.move(to: CGPoint(x: x, y: startY))
            path.addLine(to: CGPoint(x: x, y: endY))
            path.move(to: CGPoint(x: x - arrowSize, y: endY - arrowSize))
            path.addLine(to: CGPoint(x: x, y: endY))
            path.addLine(to: CGPoint(x: x + arrowSize, y: endY - arrowSize))
        }
        return path
    }
}

// We need a custom delay parser for patterns.json format "A/B"
extension MusicTheory {
    static func parsePatternDelay(_ delay: String) -> Double? {
        let components = delay.split(separator: "/")
        guard components.count == 2,
              let numerator = Double(components[0]),
              let denominator = Double(components[1]),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }
}
