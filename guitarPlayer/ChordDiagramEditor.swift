import SwiftUI

struct ChordDiagramEditor: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    // onSave receives chordName and chordDefinition (array of StringOrInt)
    let onSave: (String, [StringOrInt]) -> Void
    let onCancel: () -> Void

    @State private var chordName: String = ""
    // fret values per string: -1 = muted ('x'), 0 = open, >0 = fret number
    @State private var frets: [Int] = [0,0,0,0,0,0]

    var body: some View {
        VStack(spacing: 12) {
            Text("Create New Chord")
                .font(.title2)

            HStack(alignment: .center) {
                Text("Name")
                    .frame(width: 60, alignment: .leading)
                TextField("E.g. C_Major", text: $chordName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 300)
            }

            // Simple diagram: six strings shown left-to-right (6th -> 1st)
            HStack(spacing: 12) {
                ForEach(0..<6) { idx in
                    VStack(spacing: 6) {
                        Text(stringTopLabel(for: idx))
                            .font(.caption)
                        // visual dot showing fret
                        ZStack {
                            Rectangle()
                                .frame(width: 40, height: 120)
                                .foregroundColor(Color.black.opacity(0.05))
                                .cornerRadius(6)
                            VStack(spacing: 8) {
                                ForEach((0...5).reversed(), id: \.self) { fret in
                                    Circle()
                                        .strokeBorder(Color.gray, lineWidth: 1)
                                        .background(Circle().foregroundColor(frets[idx] == fret ? Color.blue : Color.clear))
                                        .frame(width: 18, height: 18)
                                        .onTapGesture {
                                            frets[idx] = fret
                                        }
                                }
                            }
                        }
                        // Controls for mute/open
                        HStack(spacing: 6) {
                            Button(action: { frets[idx] = -1 }) {
                                Text("X")
                                    .foregroundColor(frets[idx] == -1 ? .white : .primary)
                                    .padding(6)
                                    .background(frets[idx] == -1 ? Color.red : Color.clear)
                                    .cornerRadius(6)
                            }
                            Button(action: { frets[idx] = 0 }) {
                                Text("0")
                                    .foregroundColor(frets[idx] == 0 ? .white : .primary)
                                    .padding(6)
                                    .background(frets[idx] == 0 ? Color.green : Color.clear)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
            }

            // Numeric steppers for precision
            HStack(spacing: 12) {
                ForEach(0..<6) { idx in
                    VStack {
                        Text("S\(6-idx)")
                        Stepper(value: Binding(get: { frets[idx] }, set: { v in frets[idx] = v }), in: -1...12, step: 1) {
                            Text(frets[idx] == -1 ? "x" : "\(frets[idx])")
                        }
                        .frame(width: 80)
                    }
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Save") {
                    let normalizedName = chordName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedName.isEmpty else { return }
                    var chordDef: [StringOrInt] = []
                    for f in frets {
                        if f == -1 {
                            chordDef.append(.string("x"))
                        } else {
                            chordDef.append(.int(f))
                        }
                    }
                    onSave(normalizedName, chordDef)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding()
        .frame(minWidth: 700)
    }

    private func stringTopLabel(for index: Int) -> String {
        // index 0 is 6th string in our UI mapping
        let mapping = ["6","5","4","3","2","1"]
        return "S\(mapping[index])"
    }
}

struct ChordDiagramEditor_Previews: PreviewProvider {
    static var previews: some View {
        ChordDiagramEditor(onSave: { name, def in }, onCancel: {})
            .environmentObject(AppData())
            .environmentObject(KeyboardHandler(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), guitarPlayer: GuitarPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData()), drumPlayer: DrumPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData()), appData: AppData()))
    }
}
