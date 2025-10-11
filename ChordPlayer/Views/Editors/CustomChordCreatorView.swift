import SwiftUI

struct ChordEditorView: View {
    @Binding var chord: Chord
    var onSave: (Chord) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var midiManager: MidiManager
    
    @State private var isPlaying = false
    @State private var fretPosition: Int = 1

    @Binding var isNew: Bool

    init(chord: Binding<Chord>, isNew: Binding<Bool>, onSave: @escaping (Chord) -> Void, onCancel: @escaping () -> Void) {
        self._chord = chord
        self._isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    nameInputSection
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    FretboardView(frets: $chord.frets, fretPosition: $fretPosition)
                    
                    Stepper("Fret Position: \(fretPosition)", value: $fretPosition, in: 1...15)
                        .padding(.horizontal, 24)

                    previewSection
                        .padding(.horizontal, 24)
                    
                    actionButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            Text(isNew ? "Create Custom Chord" : "Edit Chord")
                .font(.title2).fontWeight(.bold)
            Spacer()
            Button("Cancel", role: .cancel) { onCancel() }
                .buttonStyle(.bordered)
        }
        .padding(20)
    }
    
    private var nameInputSection: some View {
        VStack(alignment: .leading) {
            Text("Chord Name").font(.headline)
            TextField("e.g., Cmaj7, Am_custom", text: $chord.name)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview").font(.headline)
            HStack(spacing: 16) {
                Button(action: playChord) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        Text(isPlaying ? "Stop" : "Audition")
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Save") { onSave(chord) }.buttonStyle(.borderedProminent)
        }
    }
    
    private func playChord() {
        if isPlaying {
            midiManager.sendPanic()
            isPlaying = false
        } else {
            let notesToPlay = chordToMidiNotes(frets: chord.frets)
            guard !notesToPlay.isEmpty else { return }

            isPlaying = true
            
            for note in notesToPlay {
                midiManager.sendNoteOn(note: UInt8(note), velocity: 100, channel: 0)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if isPlaying {
                    for note in notesToPlay {
                        midiManager.sendNoteOff(note: UInt8(note), velocity: 0, channel: 0)
                    }
                    isPlaying = false
                }
            }
        }
    }

    private func chordToMidiNotes(frets: [Int]) -> [Int] {
        let standardTuning = [64, 59, 55, 50, 45, 40] // EADGBe
        var midiNotes: [Int] = []
        for (stringIndex, fret) in frets.enumerated() {
            if fret >= 0 {
                midiNotes.append(standardTuning[stringIndex] + fret)
            }
        }
        return midiNotes
    }
}
