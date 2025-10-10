import SwiftUI

struct ChordDiagramView: View {
    let chord: Chord
    let color: Color
    let showName: Bool
    let alpha: Double

    private let fretCount = 4 // Display 4 frets for a more compact view
    private var baseFret: Int
    private var relativeFrets: [Int] = []

    init(chord: Chord, color: Color, showName: Bool = false, alpha: Double = 1.0) {
        self.chord = chord
        self.color = color
        self.showName = showName
        self.alpha = alpha

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
            let fretNumberWidth = geometry.size.width * 0.1
            let diagramGridWidth = geometry.size.width * 0.8
            
            let diagramHeight = showName ? geometry.size.height * 0.8 : geometry.size.height
            let nameHeight = showName ? geometry.size.height * 0.2 : 0
            
            let fretSpacing = (diagramHeight * 0.9) / CGFloat(fretCount + 1)
            let stringSpacing = diagramGridWidth / 5

            VStack(alignment: .leading, spacing: 0) {
                // MARK: - Chord Name
                if showName {
                    Text(chord.name)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(width: diagramGridWidth, alignment: .center) // 1. Set frame to grid width, center text inside
                        .offset(x: fretNumberWidth) // 2. Offset the whole frame to align with grid
                        .frame(height: nameHeight)
                }
                
                // MARK: - Diagram
                HStack(alignment: .top, spacing: 0) {
                    // Fret number view on the left
                    if baseFret > 1 {
                        Text("\(baseFret)")
                            .font(.system(size: fretSpacing * 0.7, weight: .semibold))
                            .foregroundColor(color)
                            .frame(width: fretNumberWidth, height:fretSpacing, alignment: .center)
                            .offset(y: fretSpacing)
                    } else {
                        // Placeholder to maintain layout consistency
                        Spacer().frame(width: fretNumberWidth)
                    }
                    
                    // Main diagram grid on the right
                    ZStack(alignment: .topLeading) {
                        drawGrid(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                        drawIndicators(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                        drawDots(stringSpacing: stringSpacing, fretSpacing: fretSpacing)
                    }
                    .frame(width: diagramGridWidth)
                }
                .frame(height: diagramHeight)
            }
        }
        .aspectRatio(showName ? 4.5/7 : 4.5/6, contentMode: .fit)
        .opacity(alpha)
    }

    private func drawGrid(stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        Path { path in
            let startX = 0.0
            for i in 0..<6 {
                let x = startX + CGFloat(i) * stringSpacing
                path.move(to: CGPoint(x: x, y: fretSpacing))
                path.addLine(to: CGPoint(x: x, y: fretSpacing + CGFloat(fretCount) * fretSpacing))
            }
            for i in 0...fretCount {
                let y = fretSpacing + CGFloat(i) * fretSpacing
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
        .position(x: (5 * stringSpacing / 2), y: fretSpacing * 0.5)
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
                    let x = CGFloat(i) * stringSpacing
                    let y = fretSpacing + CGFloat(relativeFret) * fretSpacing - (fretSpacing / 2)
                    
                    Circle()
                        .fill(color)
                        .frame(width: stringSpacing * 0.65, height: stringSpacing * 0.65)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

#if DEBUG
struct ChordDiagramView_Previews: PreviewProvider {
    static var cMajor: Chord {
        Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [0, 3, 2, 0, 1, 0])
    }

    static var gMajor: Chord {
        Chord(name: "G", frets: [5, 2, 2, 2, 2, 3], fingers: [2, 1, 0, 0, 0, 3])
    }
    
    static var aMinor7: Chord {
        Chord(name: "Am7", frets: [-1, 0, 2, 0, 1, 0], fingers: [0, 0, 2, 0, 1, 0])
    }

    static var fSharpBarre: Chord {
        Chord(name: "F#", frets: [2, 4, 4, 3, 2, 2], fingers: [1, 3, 4, 2, 1, 1])
    }

    static var previews: some View {
        VStack(spacing: 20) {
            Text("Chord Diagrams")
                .font(.largeTitle)
            
            HStack(spacing: 20) {
                ChordDiagramView(chord: cMajor, color: .primary)
                ChordDiagramView(chord: gMajor, color: .blue)
                ChordDiagramView(chord: aMinor7, color: .green)
                ChordDiagramView(chord: fSharpBarre, color: .orange)
            }
            .frame(height: 150)

            Text("With Chord Names")
                .font(.title2)

            HStack(spacing: 20) {
                ChordDiagramView(chord: cMajor, color: .primary, showName: true)
                ChordDiagramView(chord: gMajor, color: .blue, showName: true)
                ChordDiagramView(chord: aMinor7, color: .green, showName: true)
                ChordDiagramView(chord: fSharpBarre, color: .orange, showName: true)
            }
            .frame(height: 180)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
#endif
