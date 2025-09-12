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
                    editorState.activeEditorTab = .chords // Switch back to chords tab
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
    @EnvironmentObject var editorState: SheetMusicEditorState
    
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
    }
}

struct EditorLyricsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var editorState: SheetMusicEditorState
    
    @State private var editingLyric: Lyric? = nil
    @State private var isAddingInPlace = false
    @State private var newLyricContent = ""
    @FocusState private var isNewLyricFieldFocused: Bool

    private var sortedLyrics: [Lyric] {
        appData.performanceConfig.lyrics.sorted(by: { $0.earliestStartBeat ?? 0 < $1.earliestStartBeat ?? 0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                if isAddingInPlace {
                    HStack(spacing: 8) {
                        TextField("输入新歌词后按 Enter 保存", text: $newLyricContent)
                            .focused($isNewLyricFieldFocused)
                            .onSubmit {
                                if !newLyricContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    addNewLyric(content: newLyricContent)
                                }
                                newLyricContent = ""
                                isAddingInPlace = false
                            }
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)

                        Button("取消") {
                            newLyricContent = ""
                            isAddingInPlace = false
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
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
                        isAddingInPlace = true
                    }
                }
            }
            .listStyle(PlainListStyle())
            .background(Color.clear)
        }
        .padding(.top)
        .onChange(of: editorState.selectedLyricID) { newLyricID in updateHighlightedBeats(for: newLyricID) }
        .onChange(of: isAddingInPlace) { isAdding in
            if isAdding {
                isNewLyricFieldFocused = true
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
    }
}
