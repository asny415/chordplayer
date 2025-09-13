
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
    enum EditorTab { case chords, patterns, lyrics }
    @Published var activeEditorTab: EditorTab = .chords

    // The lyric ID currently selected from the sidebar lyric list.
    @Published var selectedLyricID: UUID? = nil
    
    // The beats to be highlighted in the editor, derived from the selected lyric.
    @Published var highlightedBeats: Set<Int> = []

    // The beats to be highlighted for reference, derived from the previously selected lyric.
    @Published var referenceHighlightedBeats: Set<Int> = []

    // The start beat for creating a new lyric time range.
    @Published var lyricTimeRangeStartBeat: Int? = nil

    // State for in-place lyric addition.
    @Published var isAddingLyricInPlace: Bool = false

    // State for lyric content editor sheet.
    @Published var isEditingLyricContent: Bool = false

    // Pattern IDs associated with the currently selected chord.
    @Published var associatedPatternIds: Set<String> = []
}

