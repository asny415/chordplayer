
import Foundation
import Combine

class SheetMusicEditorState: ObservableObject {
    // The beat currently selected for editing in the sheet music grid.
    @Published var selectedBeat: Int? = nil

    // The chord name selected from the sidebar chord list.
    @Published var selectedChordName: String? = nil

    // The pattern ID selected from the sidebar pattern list.
    @Published var selectedPatternId: String? = nil

    // The pattern ID currently selected for highlighting beats in the editor.
    @Published var highlightedPatternId: String? = nil
    
    // State for the shortcut assignment dialog.
    @Published var showShortcutDialog: Bool = false
    @Published var shortcutDialogData: ShortcutDialogData? = nil

    // The active tab in the editor's sidebar.
    enum EditorTab { case chords, patterns }
    @Published var activeEditorTab: EditorTab = .chords

    // Pattern IDs associated with the currently selected chord.
    @Published var associatedPatternIds: Set<String> = []
}

