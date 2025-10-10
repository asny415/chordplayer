import SwiftUI

struct ChordDiagramView: View {
    let chord: Chord
    let color: Color

    private let fretCount = 4 // Display 4 frets for a more compact view
    private var baseFret: Int
    private var relativeFrets: [Int] = []

    init(chord: Chord, color: Color) {
        self.chord = chord
        self.color = color

        let intFrets = chord.frets.filter { $0 > 0 }

        let maxFret = intFrets.max() ?? 0
        let minFret = intFrets.min() ?? 1

        if maxFret <= fretCount {
            self.baseFret = 1
        } else {
            self.baseFret = minFret
        }

        self.relativeFrets = chord.frets.map { fret in
            if fret >= self.baseFret {
                return fret - self.baseFret + 1
            } else if fret == 0 || fret == -1 {
                return fret // Keep 0 and -1 as they are for open/muted strings
            } else {
                return -1 // Treat frets below base as muted for diagram purposes
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let fretNumberWidth = geometry.size.width * 0.15
            let diagramWidth = geometry.size.width * 0.85
            
            let stringSpacing = diagramWidth / 5
            let fretSpacing = geometry.size.height / CGFloat(fretCount + 2)

            HStack(alignment: .top, spacing: 0) {
                // Fret number view on the left
                if baseFret > 1 {
                    Text("\(baseFret)")
                        .font(.system(size: fretSpacing * 0.6, weight: .semibold))
                        .foregroundColor(color)
                        .frame(width: fretNumberWidth, alignment: .trailing)
                        .padding(.trailing, 2)
                        .offset(y: fretSpacing * 1.4)
                } else {
                    // Placeholder to maintain layout consistency
                    Spacer().frame(width: fretNumberWidth + 2)
                }
                
                // Main diagram grid on the right
                ZStack(alignment: .topLeading) {
                    drawGrid(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                    drawIndicators(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                    drawDots(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                }
                .frame(width: diagramWidth)
            }
        }
        .aspectRatio(5/6, contentMode: .fit)
    }

    private func drawGrid(stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        Path { path in
            let startX = (fretSpacing / 2)
            for i in 0..<6 {
                let x = startX + CGFloat(i) * stringSpacing
                path.move(to: CGPoint(x: x, y: fretSpacing * 1.2))
                path.addLine(to: CGPoint(x: x, y: fretSpacing * 1.2 + CGFloat(fretCount) * fretSpacing))
            }
            for i in 0...fretCount {
                let y = fretSpacing * 1.2 + CGFloat(i) * fretSpacing
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: startX + 5 * stringSpacing, y: y))
            }
        }
        .stroke(color, lineWidth: 0.7)
    }

    private func drawIndicators(stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let fret = chord.frets.indices.contains(i) ? chord.frets[i] : -1
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

    private func indicator(for fret: Int) -> String {
        switch fret {
        case 0: return "○"
        case -1: return "×"
        default: return " "
        }
    }

    private func drawDots(stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let relativeFret = self.relativeFrets[i]
                if relativeFret > 0 {
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