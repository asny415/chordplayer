
import SwiftUI

struct ChordDiagramView: View {
    let frets: [StringOrInt]
    let color: Color

    private let fretCount = 4 // Display 4 frets for a more compact view
    private var baseFret: Int
    private var relativeFrets: [Int?] = []

    init(frets: [StringOrInt], color: Color) {
        self.frets = frets
        self.color = color

        let intFrets = frets.compactMap { val -> Int? in
            if case .int(let num) = val, num > 0 {
                return num
            }
            return nil
        }

        let maxFret = intFrets.max() ?? 0
        let minFret = intFrets.min() ?? 1

        if maxFret <= fretCount {
            self.baseFret = 1
        } else {
            self.baseFret = minFret
        }

        self.relativeFrets = frets.map { val in
            if case .int(let num) = val, num >= self.baseFret {
                return num - self.baseFret + 1
            }
            return nil
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let baseWidth = geometry.size.width * 0.85
            let stringSpacing = baseWidth / 5
            let fretSpacing = geometry.size.height / CGFloat(fretCount + 2)

            ZStack(alignment: .topLeading) {
                // Frets and Strings
                drawGrid(width: baseWidth, height: geometry.size.height, stringSpacing: stringSpacing, fretSpacing: fretSpacing)

                // Mute and Open String Indicators
                drawIndicators(width: baseWidth, stringSpacing: stringSpacing, fretSpacing: fretSpacing)

                // Fingering Dots
                drawDots(stringSpacing: stringSpacing, fretSpacing: fretSpacing)

                // Base Fret Indicator
                if baseFret > 1 {
                    Text("\(baseFret)fr")
                        .font(.system(size: fretSpacing * 0.6, weight: .semibold))
                        .foregroundColor(color)
                        .position(x: geometry.size.width * 0.05, y: fretSpacing * 1.5)
                }
            }
        }
        .aspectRatio(5/6, contentMode: .fit)
    }

    private func drawGrid(width: CGFloat, height: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        Path { path in
            let startX = (fretSpacing / 2)
            // Vertical lines for strings
            for i in 0..<6 {
                let x = startX + CGFloat(i) * stringSpacing
                path.move(to: CGPoint(x: x, y: fretSpacing * 1.2))
                path.addLine(to: CGPoint(x: x, y: fretSpacing * 1.2 + CGFloat(fretCount) * fretSpacing))
            }

            // Horizontal lines for frets
            for i in 0...fretCount {
                let y = fretSpacing * 1.2 + CGFloat(i) * fretSpacing
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: startX + 5 * stringSpacing, y: y))
            }
        }
        .stroke(color, lineWidth: 0.7)
    }
    
    private func drawNut(width: CGFloat, height: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        Path { path in
            let startX = (fretSpacing / 2)
            let y = fretSpacing * 1.2
            path.move(to: CGPoint(x: startX, y: y))
            path.addLine(to: CGPoint(x: startX + 5 * stringSpacing, y: y))
        }
        .stroke(color, lineWidth: 2.5)
    }


    private func drawIndicators(width: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let fret = frets.indices.contains(i) ? frets[i] : .string("x")
                let indicatorText = indicator(for: fret)
                
                Text(indicatorText)
                    .font(.system(size: stringSpacing * (indicatorText == "×" ? 0.65 : 0.5)))
                    .foregroundColor(color)
                    .frame(width: stringSpacing, height: fretSpacing)
            }
        }
        .frame(width: 5 * stringSpacing, height: fretSpacing)
        .position(x: (fretSpacing/2) + (5 * stringSpacing / 2), y: fretSpacing * 0.6)
    }

    private func indicator(for fret: StringOrInt) -> String {
        switch fret {
        case .int(0):
            return "○"
        case .string("x"):
            return "×"
        default:
            return " "
        }
    }

    private func drawDots(stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                if let relativeFret = self.relativeFrets[i] {
                    let x = (fretSpacing / 2) + CGFloat(i) * stringSpacing
                    let y = fretSpacing * 1.2 + CGFloat(relativeFret) * fretSpacing - (fretSpacing / 2)
                    
                    Circle()
                        .fill(color)
                        .frame(width: stringSpacing * 0.65, height: stringSpacing * 0.65)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

struct ChordDiagramView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 30) {
            VStack(spacing: 20) {
                Text("C Major").font(.caption)
                ChordDiagramView(frets: [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)], color: .primary)
                    .frame(width: 80, height: 96)
                
                Text("F Major (Barre)").font(.caption)
                ChordDiagramView(frets: [.int(1), .int(3), .int(3), .int(2), .int(1), .int(1)], color: .primary)
                    .frame(width: 80, height: 96)
            }
            VStack(spacing: 20) {
                Text("D# Major (High Fret)").font(.caption)
                ChordDiagramView(frets: [.string("x"), .int(6), .int(8), .int(8), .int(8), .int(6)], color: .primary)
                    .frame(width: 80, height: 96)
                
                Text("A Minor").font(.caption)
                ChordDiagramView(frets: [.string("x"), .int(0), .int(2), .int(2), .int(1), .int(0)], color: .white)
                    .frame(width: 80, height: 96)
                    .background(Color.black)
            }
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
