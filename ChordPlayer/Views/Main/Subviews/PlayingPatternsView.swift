import SwiftUI

struct PlayingPatternsView: View {
    @EnvironmentObject var appData: AppData

    @State private var patternToEdit: GuitarPattern? = nil

    var body: some View {
        VStack(alignment: .leading) {
            if let preset = appData.preset, !preset.playingPatterns.isEmpty {
                HStack {
                    Text("Playing Patterns").font(.headline)
                    Spacer()
                    Button(action: {
                        // Create a new pattern and set it as the item to be edited.
                        // Default to 8 steps of 8th notes as requested.
                        self.patternToEdit = GuitarPattern.createNew(name: "New Pattern", length: 8, resolution: .eighth)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new playing pattern")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(preset.playingPatterns) { pattern in
                        let isActive = appData.preset?.activePlayingPatternId == pattern.id
                        Button(action: {
                            appData.preset?.activePlayingPatternId = pattern.id
                            appData.saveChanges()
                        }) {
                            PlayingPatternCardView(pattern: pattern, isActive: isActive)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") {
                                self.patternToEdit = pattern
                            }
                            Button("Delete", role: .destructive) {
                                if let index = appData.preset?.playingPatterns.firstIndex(where: { $0.id == pattern.id }) {
                                    appData.removePlayingPattern(at: IndexSet(integer: index))
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    imageName: "hand.draw",
                    text: "创建演奏模式",
                    action: {
                        self.patternToEdit = GuitarPattern.createNew(name: "New Pattern", length: 8, resolution: .eighth)
                    }
                )
            }
        }
        .sheet(item: $patternToEdit) { pattern in
            // Determine if the pattern is new by checking if it already exists in the preset.
            let isNew = !(appData.preset?.playingPatterns.contains(where: { $0.id == pattern.id }) ?? false)
            
            PlayingPatternEditorSheetView(patternToEdit: pattern, isNew: isNew, onSave: { savedPattern in
                if let index = appData.preset?.playingPatterns.firstIndex(where: { $0.id == savedPattern.id }) {
                    appData.preset?.playingPatterns[index] = savedPattern
                } else {
                    appData.addPlayingPattern(savedPattern)
                }
                appData.saveChanges()
                self.patternToEdit = nil // Dismiss the sheet
            }, onCancel: {
                self.patternToEdit = nil // Dismiss the sheet
            })
        }
    }
    
    private func calculateDefaultLength(timeSignature: TimeSignature, resolution: GridResolution) -> Int {
        // Calculate the number of steps for a single measure by default
        let stepsPerMeasure = timeSignature.beatsPerMeasure * resolution.stepsPerBeat
        return Int(stepsPerMeasure)
    }
}

struct PlayingPatternCardView: View {
    let pattern: GuitarPattern
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlayingPatternView(pattern: pattern, color: .primary)
                .opacity(isActive ? 1.0 : 0.7)

            Text(pattern.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.primary)
        .padding(8)
        .frame(width: 140, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2.5 : 1)
        )
    }
}

// MARK: - Editor Sheet Wrapper View

private struct PlayingPatternEditorSheetView: View {
    @State private var pattern: GuitarPattern
    private let isNew: Bool
    private let onSave: (GuitarPattern) -> Void
    private let onCancel: () -> Void

    init(patternToEdit: GuitarPattern, isNew: Bool, onSave: @escaping (GuitarPattern) -> Void, onCancel: @escaping () -> Void) {
        self._pattern = State(initialValue: patternToEdit)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        PlayingPatternEditorView(pattern: $pattern, isNew: .constant(isNew), onSave: onSave, onCancel: onCancel)
    }
}