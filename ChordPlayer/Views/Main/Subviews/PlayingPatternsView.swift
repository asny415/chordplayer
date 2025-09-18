import SwiftUI

struct PlayingPatternsView: View {
    @EnvironmentObject var appData: AppData

    @State private var patternToEdit: GuitarPattern? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Playing Patterns").font(.headline)
                Spacer()
                Button(action: {
                    // Create a new pattern and set it as the item to be edited.
                    let timeSignature = appData.preset?.timeSignature ?? TimeSignature()
                    let defaultResolution = NoteResolution.sixteenth
                    let length = calculateDefaultLength(timeSignature: timeSignature, resolution: defaultResolution)
                    self.patternToEdit = GuitarPattern.createNew(name: "New Pattern", length: length, resolution: defaultResolution)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create a new playing pattern")
            }

            if let preset = appData.preset, !preset.playingPatterns.isEmpty {
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
                Text("No playing patterns. Click + to create one.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .center)
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
    
    private func calculateDefaultLength(timeSignature: TimeSignature, resolution: NoteResolution) -> Int {
        let beatUnit = Double(timeSignature.beatUnit)
        
        switch resolution {
        case .eighth:
            return Int(8.0 / beatUnit)
        case .sixteenth:
            return Int(16.0 / beatUnit)
        }
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
        PlayingPatternEditorView(pattern: $pattern, isNew: isNew, onSave: onSave, onCancel: onCancel)
    }
}