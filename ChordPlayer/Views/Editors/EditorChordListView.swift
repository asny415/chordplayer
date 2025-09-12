
import SwiftUI

struct EditorChordListView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var editorState: SheetMusicEditorState
    
    var onChordSelected: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("和弦进行")
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            List {
                ForEach(appData.performanceConfig.chords, id: \.id) { chordConfig in
                    let isSelected = editorState.selectedChordName == chordConfig.name
                    
                    Button(action: {
                        editorState.selectedChordName = chordConfig.name
                        // Populate associatedPatternIds
                        var associatedIds = Set<String>()
                        for (_, association) in chordConfig.patternAssociations {
                            associatedIds.insert(association.patternId)
                        }
                        editorState.associatedPatternIds = associatedIds
                        onChordSelected()
                    }) {
                        HStack {
                            Text(MusicTheory.formatChordNameForDisplayAbbreviated(chordConfig.name))
                                .font(.system(size: 12))
                            Spacer()
                            if let shortcutValue = chordConfig.shortcut, let s = Shortcut(stringValue: shortcutValue) {
                                Text(s.displayText)
                                    .font(.caption2).bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
    
    
}
