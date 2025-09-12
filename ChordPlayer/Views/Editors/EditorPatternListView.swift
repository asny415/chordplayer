
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
                        let isSelected = editorState.selectedPatternId == patternId
                        
                        Button(action: {
                            editorState.selectedPatternId = patternId
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
                        .listRowBackground(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
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
