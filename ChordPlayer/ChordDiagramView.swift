
import SwiftUI

struct ChordDiagramView: View {
    let frets: [StringOrInt]
    let color: Color

    private let fretCount = 5 // Number of frets to display

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stringSpacing = width / 6
            let fretSpacing = height / CGFloat(fretCount + 1)

            ZStack {
                // Frets and Strings
                drawGrid(width: width, height: height, stringSpacing: stringSpacing, fretSpacing: fretSpacing)

                // Mute and Open String Indicators
                drawIndicators(width: width, stringSpacing: stringSpacing, fretSpacing: fretSpacing)

                // Fingering Dots
                drawDots(width: width, stringSpacing: stringSpacing, fretSpacing: fretSpacing)
            }
        }
        .aspectRatio(5/6, contentMode: .fit)
    }

    private func drawGrid(width: CGFloat, height: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        Path { path in
            // Vertical lines for strings
            for i in 0..<6 {
                let x = stringSpacing / 2 + CGFloat(i) * stringSpacing
                path.move(to: CGPoint(x: x, y: fretSpacing / 2))
                path.addLine(to: CGPoint(x: x, y: height - fretSpacing / 2))
            }

            // Horizontal lines for frets
            for i in 0...fretCount {
                let y = fretSpacing / 2 + CGFloat(i) * fretSpacing
                path.move(to: CGPoint(x: stringSpacing / 2, y: y))
                path.addLine(to: CGPoint(x: width - stringSpacing / 2, y: y))
            }
        }
        .stroke(color, lineWidth: 0.5)
    }

    private func drawIndicators(width: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                let fret = frets.indices.contains(i) ? frets[i] : .string("x")
                Text(indicator(for: fret))
                    .font(.system(size: stringSpacing * 0.6))
                    .foregroundColor(color)
                    .frame(width: stringSpacing, height: fretSpacing)
            }
        }
        .frame(width: width, height: fretSpacing)
        .offset(y: -fretSpacing * (CGFloat(fretCount) / 2 + 0.5))
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

    private func drawDots(width: CGFloat, stringSpacing: CGFloat, fretSpacing: CGFloat) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                if let fretNumber = getFretNumber(for: i) {
                    let x = stringSpacing / 2 + CGFloat(i) * stringSpacing
                    let y = fretSpacing / 2 + CGFloat(fretNumber) * fretSpacing - (fretSpacing / 2)
                    
                    Circle()
                        .fill(color)
                        .frame(width: stringSpacing * 0.7, height: stringSpacing * 0.7)
                        .position(x: x, y: y)
                }
            }
        }
    }

    private func getFretNumber(for stringIndex: Int) -> Int? {
        guard frets.indices.contains(stringIndex) else { return nil }
        if case .int(let number) = frets[stringIndex], number > 0 {
            return number
        }
        return nil
    }
}

struct ChordDiagramView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // C Major
            ChordDiagramView(frets: [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)], color: .black)
                .frame(width: 50, height: 60)
            
            // G Major
            ChordDiagramView(frets: [.int(3), .int(2), .int(0), .int(0), .int(0), .int(3)], color: .white)
                .frame(width: 80, height: 96)
                .background(Color.gray)

            // F Major (Barre chord, simple dot representation)
            ChordDiagramView(frets: [.int(1), .int(3), .int(3), .int(2), .int(1), .int(1)], color: .blue)
                .frame(width: 100, height: 120)
        }
        .padding()
    }
}
