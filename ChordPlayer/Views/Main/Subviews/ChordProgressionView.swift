import SwiftUI
import UniformTypeIdentifiers

struct ChordProgressionView: View {
    @EnvironmentObject var appData: AppData
    @State private var showChordEditor = false
    @State private var editingChord: Chord? = nil
    @State private var newChord = Chord(name: "", frets: Array(repeating: -1, count: 6), fingers: Array(repeating: 0, count: 6))

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Part 1: The library of chords available in this preset
            VStack(alignment: .leading) {
                HStack {
                    Text("Preset Chord Library").font(.headline)
                    Spacer()
                    Button(action: {
                        editingChord = nil
                        newChord = Chord(name: "New Chord", frets: Array(repeating: 0, count: 6), fingers: Array(repeating: 0, count: 6))
                        showChordEditor = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Define a new chord for this preset")
                }

                if let preset = appData.preset, !preset.chords.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 10) {
                        ForEach(preset.chords) { chord in
                            ChordCardView(chord: chord)
                                .onDrag { NSItemProvider(object: chord.name as NSString) }
                                .contextMenu {
                                    Button("Edit") {
                                        editingChord = chord
                                        showChordEditor = true
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

            Divider()

            // Part 2: The actual chord progression
            VStack(alignment: .leading) {
                Text("Chord Progression").font(.headline)
                
                if let preset = appData.preset, !preset.chordProgression.isEmpty {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack {
                            ForEach(Array(preset.chordProgression.enumerated()), id: \.offset) { index, chordName in
                                Text(chordName)
                                    .font(.title2.weight(.semibold))
                                    .padding()
                                    .background(Material.regular, in: RoundedRectangle(cornerRadius: 8))
                                    .frame(width: 100, height: 60)
                                    .contextMenu {
                                        Button("Remove from Progression", role: .destructive) {
                                            appData.preset?.chordProgression.remove(at: index)
                                            appData.saveChanges()
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        providers.first?.loadObject(ofClass: NSString.self) { (item, error) in
                            if let chordName = item as? String {
                                DispatchQueue.main.async {
                                    appData.preset?.chordProgression.append(chordName)
                                    appData.saveChanges()
                                }
                            }
                        }
                        return true
                    }
                } else {
                    Text("Drag chords from the library above to build a progression.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .sheet(isPresented: $showChordEditor) {
            let isNew = editingChord == nil
            let chordToEdit = editingChord ?? newChord
            
            let binding = Binding<Chord>(
                get: { self.editingChord ?? self.newChord },
                set: { chord in
                    if self.editingChord != nil {
                        self.editingChord = chord
                    } else {
                        self.newChord = chord
                    }
                }
            )

            ChordEditorView(chord: binding, isNew: isNew, onSave: { savedChord in
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
}

struct ChordCardView: View {
    let chord: Chord

    var body: some View {
        VStack {
            Text(chord.name)
                .font(.title3.weight(.medium))
            
            ChordDiagramView(chord: chord, color: .primary)
        }
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}
