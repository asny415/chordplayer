
import SwiftUI

struct SheetMusicEditorWindow: View {
    // Global App Data
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    
    // Local state for the editor window
    @StateObject private var editorState = SheetMusicEditorState()
    
    // State for the escape key monitor
    @State private var escapeMonitor: Any? = nil

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
        .onAppear(perform: setupEscapeKeyMonitoring)
        .onDisappear(perform: cleanupEscapeKeyMonitoring)
    }
    
    private func setupEscapeKeyMonitoring() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                // Priority 1: If a pattern is highlighted, just clear the highlight.
                if editorState.highlightedPatternId != nil {
                    editorState.highlightedPatternId = nil
                    return nil // Consume the event
                }
                
                // Priority 2: If a beat is selected, deselect it (cancel editing).
                if editorState.selectedBeat != nil {
                    editorState.selectedBeat = nil
                    editorState.selectedChordName = nil
                    editorState.selectedPatternId = nil
                    return nil // Consume the event
                }
                
                // Priority 3: If nothing is selected or highlighted, close the window.
                dismiss()
                return nil // Consume the event
            }
            return event // Allow other events to propagate
        }
    }
    
    private func cleanupEscapeKeyMonitoring() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
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

