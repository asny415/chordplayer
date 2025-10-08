import SwiftUI

// A context object to manage which sheet to show and what data to pass to it.
fileprivate struct SheetContext: Identifiable {
    var id: String { pattern.id.uuidString }
    var pattern: DrumPattern
    let isNew: Bool
}

struct DrumPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer

    @State private var sheetContext: SheetContext?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Drum Patterns").font(.headline)

            if let preset = appData.preset, !preset.drumPatterns.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        let newPattern = DrumPattern(name: "New Beat", resolution: .sixteenth, length: 16, instruments: ["Kick", "Snare", "Hi-Hat", "Cymbal", "Tom"], midiNotes: [36, 38, 42, 49, 45])
                        sheetContext = SheetContext(pattern: newPattern, isNew: true)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new drum pattern")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(preset.drumPatterns) { pattern in
                        let isActive = appData.preset?.activeDrumPatternId == pattern.id
                        Button(action: {
                            appData.preset?.activeDrumPatternId = pattern.id
                            appData.saveChanges()
                            drumPlayer.preview(pattern: pattern)
                        }) {
                            DrumPatternCardView(pattern: pattern, isActive: isActive)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") {
                                sheetContext = SheetContext(pattern: pattern, isNew: false)
                            }
                            Button("Delete", role: .destructive) {
                                if let index = appData.preset?.drumPatterns.firstIndex(where: { $0.id == pattern.id }) {
                                    appData.removeDrumPattern(at: IndexSet(integer: index))
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(
                    imageName: "music.quarternote.3",
                    text: "创建鼓模式",
                    action: {
                        let newPattern = DrumPattern(name: "New Beat", resolution: .sixteenth, length: 16, instruments: ["Kick", "Snare", "Hi-Hat", "Cymbal", "Tom"], midiNotes: [36, 38, 42, 49, 45])
                        sheetContext = SheetContext(pattern: newPattern, isNew: true)
                    }
                )
            }
        }
        .sheet(item: $sheetContext) { context in
            DrumPatternSheetWrapper(context: context, onSave: { finalPattern in
                if let index = appData.preset?.drumPatterns.firstIndex(where: { $0.id == finalPattern.id }) {
                    appData.preset?.drumPatterns[index] = finalPattern
                } else {
                    appData.addDrumPattern(finalPattern)
                }
                appData.saveChanges()
                sheetContext = nil
            }, onCancel: {
                sheetContext = nil
            })
        }
    }
}

// This wrapper view holds the state for the editor, ensuring a clean data flow for the sheet.
private struct DrumPatternSheetWrapper: View {
    let context: SheetContext
    let onSave: (DrumPattern) -> Void
    let onCancel: () -> Void

    @State private var patternInEditor: DrumPattern

    init(context: SheetContext, onSave: @escaping (DrumPattern) -> Void, onCancel: @escaping () -> Void) {
        self.context = context
        self.onSave = onSave
        self.onCancel = onCancel
        self._patternInEditor = State(initialValue: context.pattern)
    }

    var body: some View {
        DrumPatternEditorView(
            pattern: $patternInEditor,
            isNew: context.isNew,
            onSave: { savedPattern in onSave(savedPattern) },
            onCancel: onCancel
        )
    }
}

struct DrumPatternCardView: View {
    let pattern: DrumPattern
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DrumPatternGridView(pattern: pattern, activeColor: .primary, inactiveColor: .secondary)
                .opacity(isActive ? 0.9 : 0.6)

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
