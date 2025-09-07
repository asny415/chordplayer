
import SwiftUI

struct FretboardView: View {
    @EnvironmentObject var midiManager: MidiManager
    
    // Binding to the array of fret numbers. -1: muted, 0: open, >0: fretted
    @Binding var frets: [Int]
    // The starting fret number displayed on the fretboard (e.g., 1 for open position, 5 for 5th position)
    @Binding var fretPosition: Int

    // Constants for drawing
    private let stringCount = 6
    private let displayFretCount = 7 // How many frets to show at once
    private let stringSpacing: CGFloat = 30
    private let nutWidth: CGFloat = 12
    private let dotSize: CGFloat = 10
    private let fingerDotSize: CGFloat = 22
    private let controlButtonSize: CGFloat = 24

    // Standard fret markers (3, 5, 7, 9, 12, 15...)
    private let singleMarkers = [3, 5, 7, 9, 15, 17, 19, 21]
    private let doubleMarkers = [12, 24]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // --- Mute/Open String Controls (Moved to the left) ---
            VStack(spacing: 0) {
                ForEach((0..<stringCount).reversed(), id: \.self) { stringIndex in
                    HStack(spacing: 4) {
                        // Mute Button (X)
                        Button(action: { 
                            frets[stringIndex] = -1
                            playNote(string: stringIndex, fret: -1) // -1 indicates mute, no sound
                        }) {
                            Text("X")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(frets[stringIndex] == -1 ? .white : .gray)
                                .frame(width: controlButtonSize, height: controlButtonSize)
                                .background(frets[stringIndex] == -1 ? Color.red.opacity(0.9) : Color.black.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        // Open String Button (O)
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

            // --- Fretboard Body ---
            HStack(spacing: 0) {
                // --- Nut / Fret Position Indicator ---
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

                // --- Frets and Strings ---
                ZStack {
                    // Background
                    Rectangle().fill(Color.black.opacity(0.1))

                    // Fret Wires and Markers
                    HStack(spacing: 0) {
                        ForEach(0..<displayFretCount) { fret in
                            ZStack {
                                Rectangle().frame(width: fretWidth(for: fret))
                                // Fret Markers (dots)
                                if singleMarkers.contains(fret + fretPosition) {
                                    Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                }
                                if doubleMarkers.contains(fret + fretPosition) {
                                    VStack(spacing: stringSpacing * 2) {
                                        Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                        Circle().fill(Color.gray.opacity(0.3)).frame(width: dotSize, height: dotSize)
                                    }
                                }
                                // Fret wire
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: 1.5)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Guitar Strings
                    VStack(spacing: 0) {
                        ForEach((0..<stringCount).reversed(), id: \.self) { stringIndex in
                            Rectangle()
                                .fill(LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing))
                                .frame(height: stringThickness(for: stringIndex))
                            if stringIndex < stringCount - 1 {
                                Spacer(minLength: 0)
                                    .frame(height: stringSpacing - stringThickness(for: stringIndex))
                            }
                        }
                    }

                    // --- Fingering Dots and Tap Areas ---
                    HStack(spacing: 0) {
                        ForEach(0..<displayFretCount) { fret in
                            VStack(spacing: 0) {
                                ForEach((0..<stringCount).reversed(), id: \.self) { string in
                                    ZStack {
                                        // The tappable area
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                let actualFret = fret + fretPosition
                                                if frets[string] == actualFret {
                                                    frets[string] = 0 // Toggle off to open string
                                                    playNote(string: string, fret: 0)
                                                } else {
                                                    frets[string] = actualFret
                                                    playNote(string: string, fret: actualFret)
                                                }
                                            }

                                        // The visual finger position dot
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

    // MARK: - Helper Functions
    
    private func playNote(string: Int, fret: Int) {
        guard fret >= 0 else { return } // Don't play muted notes
        
        let midiNote = MusicTheory.standardGuitarTuning[string] + fret
        guard midiNote > 0 else { return }
        
        midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100)
        
        // Schedule Note Off event to stop the sound after a short duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 100)
        }
    }
    
    private func fretWidth(for fret: Int) -> CGFloat {
        // Return a constant width for a uniform, schematic look.
        return 50
    }

    private func stringThickness(for string: Int) -> CGFloat {
        // Thicker strings for lower notes
        return CGFloat(stringCount - string) * 0.5 + 1.5
    }
}

// MARK: - Preview Provider

struct FretboardView_Previews: PreviewProvider {
    // Mock MidiManager for preview purposes
    class MockMidiManager: MidiManager {
        override func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
            print("PREVIEW: Note On: \(note)")
        }
        override func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
            print("PREVIEW: Note Off: \(note)")
        }
    }
    
    @State static private var previewFrets = [-1, 3, 2, 0, 1, 0] // Example: G Major
    @State static private var previewPosition = 1

    static var previews: some View {
        VStack {
            Spacer()
            FretboardView(frets: $previewFrets, fretPosition: $previewPosition)
                .environmentObject(MockMidiManager())
            Stepper("Fret Position: \(previewPosition)", value: $previewPosition, in: 1...15)
                .padding()
            Text("Current Frets: \(previewFrets.map { String($0) }.joined(separator: ", "))")
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
