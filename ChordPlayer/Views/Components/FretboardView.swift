import SwiftUI

struct FretboardView: View {
    @EnvironmentObject var midiManager: MidiManager
    
    @Binding var frets: [Int]
    @Binding var fretPosition: Int

    private let stringCount = 6
    private let displayFretCount = 7
    private let stringSpacing: CGFloat = 30
    private let nutWidth: CGFloat = 12
    private let dotSize: CGFloat = 10
    private let fingerDotSize: CGFloat = 22
    private let controlButtonSize: CGFloat = 24

    private let singleMarkers = [3, 5, 7, 9, 15, 17, 19, 21]
    private let doubleMarkers = [12, 24]
    
    // Dependency removed from MusicTheory
    private let standardGuitarTuning = [64, 59, 55, 50, 45, 40] // EADGBe (String 5 to 0)

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(spacing: 0) {
                ForEach((0..<stringCount).reversed(), id: \.self) { stringIndex in
                    HStack(spacing: 4) {
                        Button(action: { 
                            frets[stringIndex] = -1
                            playNote(string: stringIndex, fret: -1)
                        }) {
                            Text("X")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(frets[stringIndex] == -1 ? .white : .gray)
                                .frame(width: controlButtonSize, height: controlButtonSize)
                                .background(frets[stringIndex] == -1 ? Color.red.opacity(0.9) : Color.black.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Button(action: { 
                            frets[stringIndex] = 0
                            playNote(string: stringIndex, fret: 0)
                        }) {
                            Text("O")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(frets[stringIndex] == 0 ? .black : .gray)
                                .frame(width: controlButtonSize, height: controlButtonSize)
                                .background(frets[stringIndex] == 0 ? Color.white.opacity(0.9) : Color.black.opacity(0.2))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(frets[stringIndex] == 0 ? Color.black : Color.gray, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: stringSpacing)
                }
            }

            HStack(spacing: 0) {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: nutWidth)
                    if fretPosition > 1 {
                        Text("\(fretPosition)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary.opacity(0.8))
                    }
                }

                ZStack {
                    Rectangle().fill(Color.black.opacity(0.1))

                    HStack(spacing: 0) {
                        ForEach(0..<displayFretCount) { fret in
                            ZStack {
                                Rectangle().frame(width: fretWidth(for: fret))
                                if singleMarkers.contains(fret + fretPosition) {
                                    Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                }
                                if doubleMarkers.contains(fret + fretPosition) {
                                    VStack(spacing: stringSpacing * 2) {
                                        Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                        Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                    }
                                }
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: 1.5)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    VStack(spacing: 0) {
                        ForEach((0..<stringCount).reversed(), id: \.self) { stringIndex in
                            Rectangle()
                                .fill(LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing))
                                .frame(height: stringThickness(for: stringIndex))
                            if stringIndex > 0 {
                                Spacer(minLength: 0)
                                    .frame(height: stringSpacing - stringThickness(for: stringIndex))
                            }
                        }
                    }

                    HStack(spacing: 0) {
                        ForEach(0..<displayFretCount) { fret in
                            VStack(spacing: 0) {
                                ForEach((0..<stringCount).reversed(), id: \.self) { string in
                                    ZStack {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                let actualFret = fret + fretPosition
                                                if frets[string] == actualFret {
                                                    frets[string] = 0
                                                    playNote(string: string, fret: 0)
                                                } else {
                                                    frets[string] = actualFret
                                                    playNote(string: string, fret: actualFret)
                                                }
                                            }

                                        if frets.indices.contains(string) && frets[string] == fret + fretPosition {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.accentColor)
                                                    .frame(width: fingerDotSize, height: fingerDotSize)
                                                    .shadow(radius: 3)
                                                Text("\(frets[string])")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    }
                                    .frame(height: stringSpacing)
                                }
                            }
                            .frame(width: fretWidth(for: fret), height: CGFloat(stringCount) * stringSpacing)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: CGFloat(stringCount) * stringSpacing)
        }
        .padding(.horizontal)
    }
    
    private func playNote(string: Int, fret: Int) {
        guard fret >= 0 else { return } // Don't play muted notes
        
        let midiNote = standardGuitarTuning[string] + fret
        guard midiNote > 0 else { return }
        
        midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100, channel: 0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 0, channel: 0)
        }
    }
    
    private func fretWidth(for fret: Int) -> CGFloat {
        return 50
    }

    private func stringThickness(for string: Int) -> CGFloat {
        return CGFloat(stringCount - string) * 0.5 + 1.5
    }
}