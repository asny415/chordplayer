import SwiftUI

struct PlayingPatternsView: View {
    @EnvironmentObject var appData: AppData

    @State private var showPlayingPatternEditor: Bool = false
    @State private var editingPattern: GuitarPattern? = nil
    @State private var newPattern = GuitarPattern(name: "New Pattern", patternGrid: Array(repeating: Array(repeating: false, count: 16), count: 6), steps: 16, strings: 6)

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Playing Patterns").font(.headline)
                Spacer()
                Button(action: {
                    editingPattern = nil
                    let defaultGrid = Array(repeating: Array(repeating: false, count: 16), count: 6)
                    newPattern = GuitarPattern(name: "New Pattern", patternGrid: defaultGrid, steps: 16, strings: 6)
                    showPlayingPatternEditor = true
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
                                editingPattern = pattern
                                showPlayingPatternEditor = true
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
        .sheet(isPresented: $showPlayingPatternEditor) {
            let isNew = editingPattern == nil
            
            let binding = Binding<GuitarPattern>(
                get: { self.editingPattern ?? self.newPattern },
                set: { pattern in
                    if self.editingPattern != nil {
                        self.editingPattern = pattern
                    } else {
                        self.newPattern = pattern
                    }
                }
            )

            PlayingPatternEditorView(pattern: binding, isNew: isNew, onSave: { savedPattern in
                if let index = appData.preset?.playingPatterns.firstIndex(where: { $0.id == savedPattern.id }) {
                    appData.preset?.playingPatterns[index] = savedPattern
                } else {
                    appData.addPlayingPattern(savedPattern)
                }
                appData.saveChanges()
                showPlayingPatternEditor = false
            }, onCancel: {
                showPlayingPatternEditor = false
            })
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
