
import SwiftUI

struct SheetMusicEditorWindow: View {
    // Global App Data
    @EnvironmentObject var appData: AppData
    
    // Local state for the editor window
    @StateObject private var editorState = SheetMusicEditorState()

    var body: some View {
        HSplitView {
            // Main Content: The Editor
            SheetMusicEditorView()
                .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)

            // Sidebar: The Libraries
            EditorLibraryView()
                .frame(minWidth: 280, maxWidth: 450)
        }
        .navigationTitle("曲谱编辑器")
        .frame(minWidth: 900, minHeight: 550)
        // Provide the local editor state to all children of this window
        .environmentObject(editorState)
    }
}

struct EditorLibraryView: View {
    // Using a local enum for tab identifiers for clarity
    enum Tab {
        case chords
        case patterns
    }
    
    @State private var activeTab: Tab = .chords
    
    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: $activeTab) {
                // Tab 1: Chords for the current preset
                EditorChordListView(onChordSelected: {
                    // When a chord is selected, automatically switch to the patterns tab
                    activeTab = .patterns
                })
                .tabItem {
                    Label("和弦进行", systemImage: "guitars.fill")
                }
                .tag(Tab.chords)
                
                // Tab 2: Patterns for the current preset
                EditorPatternListView()
                .tabItem {
                    Label("演奏指法", systemImage: "hand.draw.fill")
                }
                .tag(Tab.patterns)
            }
        }
        .background(.ultraThickMaterial)
    }
}

