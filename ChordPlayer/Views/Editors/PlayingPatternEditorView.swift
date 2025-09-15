import SwiftUI

struct PlayingPatternEditorView: View {
    @Binding var pattern: GuitarPattern
    var onSave: (GuitarPattern) -> Void
    var onCancel: () -> Void

    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager

    private var isNew: Bool

    init(pattern: Binding<GuitarPattern>, isNew: Bool, onSave: @escaping (GuitarPattern) -> Void, onCancel: @escaping () -> Void) {
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
        .frame(minWidth: 700, idealWidth: 800, minHeight: 450)
        .background(Color(.windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            Text(isNew ? "Create Playing Pattern" : "Edit Playing Pattern")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            TextField("Pattern Name", text: $pattern.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 250)
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 20) {
            Text("Strings: \(pattern.strings), Steps: \(pattern.steps)").font(.headline)
            Spacer()
            Button("Preview with C Major") { chordPlayer.previewPattern(pattern) }
        }
    }

    private var gridEditorView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(1...pattern.strings, id: \.self) { i in
                    Text("String \(i)").font(.subheadline).frame(height: 35, alignment: .leading)
                }
            }
            .frame(width: 80)
            
            GeometryReader { geometry in
                let stepWidth = max(10, (geometry.size.width - CGFloat(pattern.steps - 1) * 2) / CGFloat(pattern.steps))
                ScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        let stepsPerBeat = 4 // Assuming 4/4
                        ForEach(0..<pattern.steps, id: \.self) { col in
                            VStack(spacing: 2) {
                                ForEach(0..<pattern.strings, id: \.self) { row in
                                    gridCell(row: row, col: col, size: stepWidth)
                                }
                            }
                            .background((col / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1))
                            if (col + 1) % stepsPerBeat == 0 && col < pattern.steps - 1 {
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
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.2))
            .frame(width: size, height: 35)
            .onTapGesture { pattern.patternGrid[row][col].toggle() }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel", role: .cancel) { onCancel() }
            Spacer()
            Button("Save") { onSave(pattern) }.buttonStyle(.borderedProminent)
        }
    }
    
    
}