
import SwiftUI

struct EditorPatternListView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var editorState: SheetMusicEditorState
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("演奏指法")
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            List {
                ForEach(Array(appData.performanceConfig.selectedPlayingPatterns.enumerated()), id: \.element) { index, patternId in
                    if let details = findPlayingPatternDetails(for: patternId) {
                        let isSelected = (editorState.selectedBeat != nil) ? (editorState.selectedPatternId == patternId) : (editorState.highlightedPatternId == patternId)
                        
                        Button(action: {
                            if editorState.selectedBeat != nil {
                                // We are in cell-editing mode, so apply the pattern to the beat.
                                editorState.selectedPatternId = patternId
                            } else {
                                // We are not in cell-editing mode, so toggle the highlight.
                                if editorState.highlightedPatternId == patternId {
                                    editorState.highlightedPatternId = nil // Toggle off
                                } else {
                                    editorState.highlightedPatternId = patternId // Highlight this pattern
                                }
                            }
                        }) {
                            HStack {
                                Text(details.pattern.name)
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            Group {
                                if isSelected {
                                    Color.accentColor.opacity(0.3)
                                } else if editorState.selectedChordName != nil && editorState.associatedPatternIds.contains(patternId) {
                                    Color.blue.opacity(0.2) // Highlight color for associated patterns
                                } else {
                                    Color.clear
                                }
                            }
                        )
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
    
    private func findPlayingPatternDetails(for patternId: String) -> (pattern: GuitarPattern, category: String)? {
        // This is still inefficient, but we are addressing the state management first.
        // A future optimization would be to cache these details.
        for (_, patterns) in customPlayingPatternManager.customPlayingPatterns {
            if let pattern = patterns.first(where: { $0.id == patternId }) {
                return (pattern, "自定义")
            }
        }
        
        if let library = appData.patternLibrary {
            for (category, patterns) in library {
                if let pattern = patterns.first(where: { $0.id == patternId }) {
                    return (pattern, category)
                }
            }
        }
        
        return nil
    }
}
