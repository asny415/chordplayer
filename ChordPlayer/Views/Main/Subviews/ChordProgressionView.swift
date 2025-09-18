import SwiftUI
import UniformTypeIdentifiers

struct ChordProgressionView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    
    @State private var chordToEdit: Chord = .init(name: "", frets: Array(repeating: -1, count: 6), fingers: Array(repeating: 0, count: 6))
    @State private var isNewChord: Bool = false
    @State private var showChordEditor: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Part 1: The library of chords available in this preset
            VStack(alignment: .leading) {
                HStack {
                    Text("Preset Chord Library").font(.headline)
                    Spacer()
                    Button(action: {
                        self.isNewChord = true
                        self.chordToEdit = Chord(name: "New Chord", frets: Array(repeating: 0, count: 6), fingers: Array(repeating: 0, count: 6))
                        self.showChordEditor = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Define a new chord for this preset")
                }

                if let preset = appData.preset, !preset.chords.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 10) {
                        ForEach(preset.chords) { chord in
                            Button(action: {
                                playChord(chord)
                            }) {
                                ChordCardView(chord: chord)
                            }
                            .buttonStyle(.plain)
                            .onDrag { NSItemProvider(object: chord.name as NSString) }
                            .contextMenu {
                                Button("Edit") {
                                    self.isNewChord = false
                                    self.chordToEdit = chord
                                    self.showChordEditor = true
                                }
                                Button("Delete", role: .destructive) {
                                    if let index = appData.preset?.chords.firstIndex(where: { $0.id == chord.id }) {
                                        appData.removeChord(at: IndexSet(integer: index))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No chords defined in this preset. Click + to add one.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                }
            }

        }
        .sheet(isPresented: $showChordEditor) {
            ChordEditorView(chord: $chordToEdit, isNew: self.isNewChord, onSave: { savedChord in
                if let index = appData.preset?.chords.firstIndex(where: { $0.id == savedChord.id }) {
                    appData.preset?.chords[index] = savedChord
                } else {
                    appData.addChord(savedChord)
                }
                appData.saveChanges()
                showChordEditor = false
            }, onCancel: {
                showChordEditor = false
            })
        }
    }
    
    private func playChord(_ chord: Chord) {
        guard let preset = appData.preset, let activePatternId = preset.activePlayingPatternId else { return }
        if let activePattern = preset.playingPatterns.first(where: { $0.id == activePatternId }) {
            // Calculate a sensible duration for the pattern based on its properties
            let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
            let stepsPerWholeNote = activePattern.resolution == .sixteenth ? 16.0 : 8.0
            let singleStepDuration = wholeNoteSeconds / stepsPerWholeNote
            let totalDuration = singleStepDuration * Double(activePattern.length)

            chordPlayer.schedulePattern(
                chord: chord, 
                pattern: activePattern, 
                preset: preset, 
                scheduledUptime: ProcessInfo.processInfo.systemUptime, // Play immediately
                totalDuration: totalDuration, 
                dynamics: .medium,
                completion: { _ in }
            )
        }
    }
}

struct ChordCardView: View {
    let chord: Chord

    var body: some View {
        VStack {
            Text(chord.name)
                .font(.headline)
            
            ChordDiagramView(chord: chord, color: .primary)
        }
        .padding(6)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}