
import SwiftUI

struct TimelineRulerView: View {
    let lengthInBeats: Double
    let timeSignature: TimeSignature
    let pixelsPerBeat: CGFloat

    var body: some View {
        Canvas { context, size in
            
            let beatsPerMeasure = Double(timeSignature.beatsPerMeasure)
            let totalMeasures = Int(ceil(lengthInBeats / beatsPerMeasure))

            // Draw measure lines and numbers
            for measure in 0...totalMeasures {
                let x = CGFloat(Double(measure) * beatsPerMeasure) * pixelsPerBeat
                if x <= size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(.secondary), lineWidth: 1)
                    
                    let textPosition = CGPoint(x: x + (CGFloat(beatsPerMeasure) * pixelsPerBeat / 2.0), y: 12)
                    context.draw(Text("\(measure + 1)").font(.caption2).foregroundColor(.secondary), at: textPosition)
                }
            }

            // Draw beat lines
            for beat in 0..<Int(lengthInBeats) {
                let x = CGFloat(beat) * pixelsPerBeat
                if x <= size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height * 0.5))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 0.5)
                }
            }
        }
        .background(Color.gray.opacity(0.2))
    }
}
