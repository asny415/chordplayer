import SwiftUI

struct DrumPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer

    @State private var showDrumPatternEditor: Bool = false
    @State private var editingPattern: DrumPattern? = nil
    @State private var newPattern = DrumPattern(name: "New Drum Beat", patternGrid: Array(repeating: Array(repeating: false, count: 16), count: 3), steps: 16, instruments: ["Kick", "Snare", "Hi-Hat"])

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Drum Patterns").font(.headline)
                Spacer()
                Button(action: {
                    editingPattern = nil
                    let defaultGrid = Array(repeating: Array(repeating: false, count: 16), count: 3)
                    newPattern = DrumPattern(name: "New Drum Beat", patternGrid: defaultGrid, steps: 16, instruments: ["Kick", "Snare", "Hi-Hat"])
                    showDrumPatternEditor = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create a new drum pattern")
            }

            if let preset = appData.preset, !preset.drumPatterns.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(preset.drumPatterns) { pattern in
                        let isActive = appData.preset?.activeDrumPatternId == pattern.id
                        Button(action: {
                            appData.preset?.activeDrumPatternId = pattern.id
                            appData.saveChanges()
                            drumPlayer.playActivePattern()
                        }) {
                            DrumPatternCardView(pattern: pattern, isActive: isActive)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit") {
                                editingPattern = pattern
                                showDrumPatternEditor = true
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
                Text("No drum patterns. Click + to create one.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 80, alignment: .center)
            }
        }
        .sheet(isPresented: $showDrumPatternEditor) {
            let isNew = editingPattern == nil
            let patternToEdit = editingPattern ?? newPattern
            
            let binding = Binding<DrumPattern>(
                get: { self.editingPattern ?? self.newPattern },
                set: { pattern in
                    if self.editingPattern != nil {
                        self.editingPattern = pattern
                    } else {
                        self.newPattern = pattern
                    }
                }
            )

            DrumPatternEditorView(pattern: binding, isNew: isNew, onSave: { savedPattern in
                if let index = appData.preset?.drumPatterns.firstIndex(where: { $0.id == savedPattern.id }) {
                    appData.preset?.drumPatterns[index] = savedPattern
                } else {
                    appData.addDrumPattern(savedPattern)
                }
                appData.saveChanges()
                showDrumPatternEditor = false
            }, onCancel: {
                showDrumPatternEditor = false
            })
        }
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
