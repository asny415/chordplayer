import SwiftUI

struct SheetMusicEditorWindow: View {
    // Global App Data
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss
    
    // Local state for the editor window
    @StateObject private var editorState = SheetMusicEditorState()
    
    // State for delete confirmation
    @State private var showDeleteConfirmation: Bool = false
    
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
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) { performDeletion() }
            Button("取消", role: .cancel) { }
        } message: {
            if let beat = editorState.selectedBeat {
                Text("您确定要删除第 \(beat + 1) 拍上的所有和弦和指法关联吗？此操作无法撤销。")
            } else {
                Text("此操作无法撤销。")
            }
        }
        .onAppear(perform: setupGlobalKeyMonitoring)
        .onDisappear(perform: cleanupGlobalKeyMonitoring)
    }
    
    private func performDeletion() {
        guard let beatToDelete = editorState.selectedBeat else { return }

        var newConfig = appData.performanceConfig

        for chordIndex in 0..<newConfig.chords.count {
            var chordConfig = newConfig.chords[chordIndex]
            var shortcutsToRemove: [Shortcut] = []
            
            for (shortcut, association) in chordConfig.patternAssociations {
                if var beatIndices = association.beatIndices, beatIndices.contains(beatToDelete) {
                    
                    beatIndices.removeAll { $0 == beatToDelete }
                    
                    if beatIndices.isEmpty {
                        shortcutsToRemove.append(shortcut)
                    } else {
                        var mutableAssociation = association
                        mutableAssociation.beatIndices = beatIndices
                        chordConfig.patternAssociations[shortcut] = mutableAssociation
                    }
                }
            }
            
            for shortcut in shortcutsToRemove {
                chordConfig.patternAssociations.removeValue(forKey: shortcut)
            }
            
            newConfig.chords[chordIndex] = chordConfig
        }

        appData.performanceConfig = newConfig
        editorState.selectedBeat = nil
    }
    
    private func setupGlobalKeyMonitoring() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle Delete/Backspace
            // Key code 51 is backspace, 117 is forward delete.
            if event.keyCode == 51 || event.keyCode == 117 {
                if self.editorState.selectedBeat != nil {
                    self.showDeleteConfirmation = true
                    return nil // Consume the event
                }
            }
            
            // Handle ESC
            if event.keyCode == 53 { // ESC key
                // Priority 1: If shortcut dialog is open, let it handle ESC.
                if editorState.showShortcutDialog {
                    return event // Don't consume, let the dialog handle it
                }

                // Priority 2: If lyric content editor sheet is open, let it handle ESC.
                if editorState.isEditingLyricContent {
                    return event // Don't consume, let the sheet handle it
                }

                // Priority 3: If in-place lyric addition is active, cancel it.
                if editorState.isAddingLyricInPlace {
                    editorState.isAddingLyricInPlace = false
                    return nil // Consume the event
                }

                // Priority 4: If a lyric time range is being selected, cancel it.
                if editorState.lyricTimeRangeStartBeat != nil {
                    editorState.lyricTimeRangeStartBeat = nil
                    return nil // Consume the event
                }
                
                // Priority 5: If a lyric is selected, deselect it.
                if editorState.selectedLyricID != nil {
                    editorState.selectedLyricID = nil
                    return nil // Consume the event
                }

                // Priority 6: If a pattern is highlighted, just clear the highlight.
                if editorState.highlightedPatternId != nil {
                    editorState.highlightedPatternId = nil
                    return nil // Consume the event
                }
                
                // Priority 7: If a beat is selected, deselect it (cancel editing).
                if editorState.selectedBeat != nil {
                    editorState.selectedBeat = nil
                    editorState.selectedChordName = nil
                    editorState.selectedPatternId = nil
                    editorState.activeEditorTab = .chords // Switch back to chords tab
                    return nil // Consume the event
                }
                
                // Priority 8: If nothing is selected or highlighted, close the window.
                dismiss()
                return nil // Consume the event
            }
            return event // Allow other events to propagate
        }
    }
    
    private func cleanupGlobalKeyMonitoring() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}

struct EditorLibraryView: View {
    @EnvironmentObject var editorState: SheetMusicEditorState
    @EnvironmentObject var appData: AppData // Needed for default reference
    
    var body: some View {
        VStack(alignment: .leading) {
            TabView(selection: $editorState.activeEditorTab) {
                // Tab 1: Chords for the current preset
                EditorChordListView(onChordSelected: {
                    // When a chord is selected, automatically switch to the patterns tab
                    editorState.activeEditorTab = .patterns
                })
                .tabItem {
                    Label("和弦进行", systemImage: "guitars.fill")
                }
                .tag(SheetMusicEditorState.EditorTab.chords)
                
                // Tab 2: Patterns for the current preset
                EditorPatternListView()
                .tabItem {
                    Label("演奏指法", systemImage: "hand.draw.fill")
                }
                .tag(SheetMusicEditorState.EditorTab.patterns)
                
                // Tab 3: Lyrics
                EditorLyricsView()
                .tabItem {
                    Label("歌词", systemImage: "music.mic")
                }
                .tag(SheetMusicEditorState.EditorTab.lyrics)
            }
        }
        .background(.ultraThickMaterial)
        .onChange(of: editorState.activeEditorTab) { _, newTab in
            if newTab == .lyrics {
                setDefaultReferenceHighlight()
            }
        }
    }
    
    private func setDefaultReferenceHighlight() {
        // Only set default if no lyric is selected and reference is empty
        guard editorState.selectedLyricID == nil && editorState.referenceHighlightedBeats.isEmpty else { return }

        // Find the last lyric with a time range, sorted by the start of the range
        guard let lastLyricWithRange = appData.performanceConfig.lyrics.filter({ !$0.timeRanges.isEmpty }).sorted(by: { $0.earliestStartBeat ?? 0 < $1.earliestStartBeat ?? 0 }).last else { return }

        // Find the last time range within that lyric, also sorted
        guard let lastRange = lastLyricWithRange.timeRanges.sorted(by: { $0.startBeat < $1.startBeat }).last else { return }

        // Set the reference highlight
        editorState.referenceHighlightedBeats = Set(lastRange.startBeat...lastRange.endBeat)
    }
}

struct EditorLyricsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var editorState: SheetMusicEditorState
    
    @State private var editingLyric: Lyric? = nil
    @State private var newLyricContent = ""
    @FocusState private var isNewLyricFieldFocused: Bool

    private var sortedLyrics: [Lyric] {
        appData.performanceConfig.lyrics.sorted(by: { $0.earliestStartBeat ?? 0 < $1.earliestStartBeat ?? 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    ForEach(sortedLyrics) { lyric in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lyric.content)
                                    .font(.body)
                                    .lineLimit(nil)
                                
                                Text(formatTimeRangesDisplay(lyric.timeRanges))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer()

                            if editorState.selectedLyricID == lyric.id {
                                Button(action: { editingLyric = lyric }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.accentColor)
                                .padding(.trailing, 4)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(editorState.selectedLyricID == lyric.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1) {
                            editorState.selectedLyricID = (editorState.selectedLyricID == lyric.id) ? nil : lyric.id
                        }
                    }
                    
                    // In-place add new lyric row
                    if editorState.isAddingLyricInPlace {
                        HStack(spacing: 8) {
                            TextField("输入新歌词后按 Enter 保存", text: $newLyricContent)
                                .focused($isNewLyricFieldFocused)
                                .onSubmit {
                                    if !newLyricContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        addNewLyric(content: newLyricContent)
                                    }
                                    newLyricContent = ""
                                    isNewLyricFieldFocused = true // Keep focus for next lyric
                                    // Scroll to the new input field
                                    DispatchQueue.main.async {
                                        proxy.scrollTo("newLyricInputRow", anchor: .bottom)
                                    }
                                }
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)

                            Button("取消") {
                                newLyricContent = ""
                                editorState.isAddingLyricInPlace = false
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .id("newLyricInputRow") // Assign an ID to this row
                    } else {
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle")
                            Text("添加新歌词")
                            Spacer()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editorState.isAddingLyricInPlace = true
                            // Scroll to the new input field when it appears
                            DispatchQueue.main.async {
                                proxy.scrollTo("newLyricInputRow", anchor: .bottom)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.clear)
            }
        }
        .padding(.top)
        .onChange(of: editorState.selectedLyricID) { _, newLyricID in
            // Before updating to the new lyric's highlights, save the old ones for reference.
            if editorState.highlightedBeats != editorState.referenceHighlightedBeats {
                editorState.referenceHighlightedBeats = editorState.highlightedBeats
            }
            updateHighlightedBeats(for: newLyricID)
        }
        .onChange(of: editorState.isAddingLyricInPlace) { _, isAdding in
            if isAdding {
                isNewLyricFieldFocused = true
            } else {
                newLyricContent = "" // Clear content when exiting in-place add
            }
        }
        .sheet(item: $editingLyric) { lyric in
            LyricContentEditorSheet(lyric: lyric) { newContent in
                updateLyricContent(lyricID: lyric.id, newContent: newContent)
            }
        }
    }
    
    private func addNewLyric(content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var newConfig = appData.performanceConfig
        let newLyric = Lyric(content: content)
        newConfig.lyrics.append(newLyric)
        appData.performanceConfig = newConfig
    }
    
    private func updateLyricContent(lyricID: UUID, newContent: String) {
        var newConfig = appData.performanceConfig
        
        if newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newConfig.lyrics.removeAll { $0.id == lyricID }
            if editorState.selectedLyricID == lyricID {
                editorState.selectedLyricID = nil
            }
        } else {
            if let index = newConfig.lyrics.firstIndex(where: { $0.id == lyricID }) {
                newConfig.lyrics[index].content = newContent
            }
        }
        
        appData.performanceConfig = newConfig
    }
    
    private func updateHighlightedBeats(for lyricID: UUID?) {
        DispatchQueue.main.async {
            guard let lyricID = lyricID,
                  let lyric = appData.performanceConfig.lyrics.first(where: { $0.id == lyricID }) else {
                editorState.highlightedBeats = []
                return
            }
            
            var beats = Set<Int>()
            for timeRange in lyric.timeRanges {
                let start = max(1, timeRange.startBeat)
                let end = timeRange.endBeat
                if end >= start {
                    beats.formUnion(start...end)
                }
            }
            editorState.highlightedBeats = beats
        }
    }
    
    private func formatTimeRangesDisplay(_ timeRanges: [LyricTimeRange]) -> String {
        if timeRanges.isEmpty {
            return "无时间段"
        }
        
        let sorted = timeRanges.sorted { $0.startBeat < $1.startBeat }
        let rangeStrings = sorted.map { "第 \($0.startBeat)-\($0.endBeat) 拍" }
        let totalBeats = timeRanges.reduce(0) { $0 + $1.durationBeats }
        
        return rangeStrings.joined(separator: ", ") + " (共 \(totalBeats) 拍)"
    }
}

struct LyricContentEditorSheet: View {
    let lyric: Lyric
    let onSave: (String) -> Void
    
    @EnvironmentObject var editorState: SheetMusicEditorState
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    
    init(lyric: Lyric, onSave: @escaping (String) -> Void) {
        self.lyric = lyric
        self.onSave = onSave
        self._content = State(initialValue: lyric.content)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(lyric.content.isEmpty ? "添加歌词" : "编辑歌词")
                .font(.title2)
                .fontWeight(.bold)

            TextEditor(text: $content)
                .font(.body)
                .frame(height: 150)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("保存") {
                    onSave(content)
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 450, height: 300)
        .onAppear { editorState.isEditingLyricContent = true }
        .onDisappear { editorState.isEditingLyricContent = false }
    }
}
