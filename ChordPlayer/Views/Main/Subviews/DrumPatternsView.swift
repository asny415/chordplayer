import SwiftUI

// A context object to manage which sheet to show and what data to pass to it.
fileprivate struct SheetContext: Identifiable {
    var id: String { pattern.id.uuidString }
    var pattern: DrumPattern
    let isNew: Bool
}

// The new content view for the generic SegmentCardView
struct DrumPatternCardContent: View {
    let pattern: DrumPattern
    let isActive: Bool

    var body: some View {
        DrumPatternGridView(pattern: pattern, activeColor: .primary, inactiveColor: .secondary)
            .opacity(isActive ? 0.9 : 0.6)
    }
}

struct DrumPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer

    @State private var sheetContext: SheetContext?

    var body: some View {
        VStack(alignment: .leading) {
            if let preset = appData.preset, !preset.drumPatterns.isEmpty {
                HStack {
                    Text("Drum Patterns").font(.headline)
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
                        
                        SegmentCardView(
                            title: pattern.name,
                            systemImageName: "music.quarternote.3",
                            isSelected: isActive
                        ) {
                            DrumPatternCardContent(pattern: pattern, isActive: isActive)
                        }
                        .onTapGesture(count: 2) {
                            sheetContext = SheetContext(pattern: pattern, isNew: false)
                        }
                        .onTapGesture {
                            appData.preset?.activeDrumPatternId = isActive ? nil : pattern.id
                            appData.saveChanges()
                            if !isActive {
                                drumPlayer.preview(pattern: pattern)
                            }
                        }
                        .contextMenu {
                            Button("Add to Drum Track") {
                                addToDrumTrack(pattern: pattern)
                            }
                            Divider()
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
    
    private func addToDrumTrack(pattern: DrumPattern) {
        guard appData.preset != nil else { return }
        
        // 1. Get the drum track
        let drumTrack = appData.preset!.arrangement.drumTrack
        
        // 2. Calculate the end beat of the last segment
        let lastBeat = drumTrack.segments.map { $0.startBeat + $0.durationInBeats }.max() ?? 0.0
        
        // 3. Calculate the duration of the new segment in beats
        let beatsPerStep = pattern.resolution == .sixteenth ? 0.25 : 0.5
        let durationInBeats = Double(pattern.length) * beatsPerStep
        
        // 4. Create the new drum segment
        let newSegment = DrumSegment(
            startBeat: lastBeat,
            durationInBeats: durationInBeats,
            patternId: pattern.id
        )
        
        // 5. Add the segment and save
        appData.preset?.arrangement.drumTrack.segments.append(newSegment)
        appData.saveChanges()
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