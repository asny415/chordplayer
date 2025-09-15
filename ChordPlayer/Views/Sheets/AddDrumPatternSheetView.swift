import SwiftUI

struct DrumPatternEditorView: View {
    @Binding var pattern: DrumPattern
    var onSave: (DrumPattern) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var drumPlayer: DrumPlayer
    
    @State private var bpm: Double = 120.0

    private var isNew: Bool

    init(pattern: Binding<DrumPattern>, isNew: Bool, onSave: @escaping (DrumPattern) -> Void, onCancel: @escaping () -> Void) {
        self._pattern = pattern
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 12) {
            headerView.padding()
            Divider()
            toolbarView.padding(.horizontal)
            gridEditorView.padding()
            Spacer()
            Divider()
            footerButtons.padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 500)
        .background(Color(.windowBackgroundColor))
        .onDisappear { drumPlayer.stop() }
    }

    private var headerView: some View {
        HStack {
            Text(isNew ? "Create Drum Pattern" : "Edit Drum Pattern")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            TextField("Pattern Name", text: $pattern.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 250)
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Picker("Resolution", selection: $pattern.resolution) {
                    ForEach(NoteResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            VStack(alignment: .leading) {
                Stepper(value: $pattern.length, in: 4...64, step: 4) { 
                    Text("Length: \(pattern.length) steps")
                }
            }
            
            Spacer()
            
            HStack {
                Text("Preview BPM:")
                Stepper(value: $bpm, in: 40...240, step: 1) { Text("\(Int(bpm))") }
            }
        }
    }

    private var gridEditorView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(pattern.instruments, id: \.self) { name in
                    Text(name).font(.headline).frame(height: 35, alignment: .leading)
                }
            }
            .frame(width: 80)
            
            GeometryReader { geometry in
                let stepWidth = max(10, (geometry.size.width - CGFloat(pattern.length - 1) * 2) / CGFloat(pattern.length))
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        let stepsPerBeat = pattern.resolution == .sixteenth ? 4 : 2
                        ForEach(0..<pattern.length, id: \.self) { col in
                            VStack(spacing: 2) {
                                ForEach(0..<pattern.instruments.count, id: \.self) { row in
                                    gridCell(row: row, col: col, size: stepWidth)
                                }
                            }
                            .background((col / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1))
                            if (col + 1) % stepsPerBeat == 0 && col < pattern.length - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func gridCell(row: Int, col: Int, size: CGFloat) -> some View {
        let isActive = pattern.patternGrid[row][col]
        return RoundedRectangle(cornerRadius: 4)
            .fill(isActive ? colorForInstrument(at: row) : Color.primary.opacity(0.2))
            .frame(width: size, height: 35)
            .onTapGesture {
                pattern.patternGrid[row][col].toggle()
                if pattern.patternGrid[row][col] {
                    let midiNote = pattern.midiNotes[row]
                    drumPlayer.playNote(midiNote: midiNote)
                }
            }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
            Spacer()
            Button(action: togglePlayback) {
                Image(systemName: drumPlayer.isPreviewing ? "stop.fill" : "play.fill")
            }.frame(width: 50)
            Spacer()
            Button("Save") { onSave(pattern) }.buttonStyle(.borderedProminent)
        }
    }
    
    private func togglePlayback() {
        if drumPlayer.isPreviewing {
            drumPlayer.stop()
        } else {
            drumPlayer.previewPattern(pattern, bpm: bpm)
        }
    }

    private func colorForInstrument(at index: Int) -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .cyan, .green, .purple]
        return colors[index % colors.count].opacity(0.8)
    }
}
