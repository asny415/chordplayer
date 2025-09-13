
import SwiftUI
import AppKit

struct SheetMusicEditorView: View {
    @EnvironmentObject var appData: AppData // For song data
    @EnvironmentObject var editorState: SheetMusicEditorState // For local editor state
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    // 快捷键对话框状态
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any? = nil
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    @State private var hoveredBeat: Int? = nil
    @State private var cachedTotalBeats: Int = 0
    @State private var cachedMaxMeasure: Int = 0
    @State private var cachedTotalMeasures: Int = 0
    
    private var beatsPerMeasure: Int {
        let timeSigParts = appData.performanceConfig.timeSignature.split(separator: "/")
        return Int(timeSigParts.first.map(String.init) ?? "4") ?? 4
    }
    
    // 自动长度：总节拍数+1小节（直接从配置计算，而非autoPlaySchedule）
    private var totalBeats: Int {
        cachedTotalBeats
    }
    
    // 直接从配置数据计算最大拍号
    private func getCurrentMaxBeatFromConfig() -> Int {
        var maxBeat = -1
        
        for chordConfig in appData.performanceConfig.chords {
            for (_, association) in chordConfig.patternAssociations {
                if let beatIndices = association.beatIndices {
                    if let localMax = beatIndices.max() {
                        maxBeat = max(maxBeat, localMax)
                    }
                }
            }
        }
        
        return maxBeat
    }
    
    private func recalculateTotalBeats() {
        let currentMaxBeat = getCurrentMaxBeatFromConfig()

        let maxMeasure = currentMaxBeat < 0 ? 0 : (currentMaxBeat / beatsPerMeasure) + 1
        let totalMeasures = (maxMeasure == 0 ? 4 : maxMeasure) + 1
        
        self.cachedMaxMeasure = maxMeasure
        self.cachedTotalMeasures = totalMeasures
        
        let beats: Int
        if currentMaxBeat < 0 {
            // 没有任何数据，默认4小节 + 1额外小节 = 5小节
            beats = 5 * beatsPerMeasure
        } else {
            // 计算当前最大拍号所在的小节数（从1开始）
            let maxMeasureNumber = (currentMaxBeat / beatsPerMeasure) + 1
            // 总小节数 = 最大小节数 + 1额外小节
            beats = (maxMeasureNumber + 1) * beatsPerMeasure
        }
        self.cachedTotalBeats = beats
    }
    
    private var beatsPerRow: Int {
        // 4/4: 6 measures * 4 beats/measure = 24 beats
        // 3/4: 8 measures * 3 beats/measure = 24 beats
        // 6/8: 4 measures * 6 beats/measure = 24 beats
        return 24
    }
    
    private var numberOfRows: Int {
        return Int(ceil(Double(totalBeats) / Double(beatsPerRow)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            pianoRollView
            if editorState.selectedBeat != nil {
                editingControlsView
            }
        }
        .padding()
        .alert("快捷键冲突", isPresented: $showConflictAlert) { Button("确定") { } } message: { Text(conflictMessage) }
        .onAppear(perform: recalculateTotalBeats)
        .onChange(of: appData.performanceConfig) { recalculateTotalBeats() }
        .onDisappear(perform: cleanupCaptureMonitor)
        // When selections from the sidebar change, trigger the auto-apply logic.
        .onChange(of: editorState.selectedChordName) { checkAndAutoApply() }
        .onChange(of: editorState.selectedPatternId) { checkAndAutoApply() }
        .overlay(
            Group {
                if editorState.showShortcutDialog {
                    shortcutDialogView
                }
            }
        )
    }
    
    private var headerView: some View {
        HStack {
            Text("曲谱编辑")
                .font(.headline)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("最大小节: \(cachedMaxMeasure) | 总长度: \(cachedTotalMeasures)小节")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("总拍数: \(totalBeats)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
    
    private var pianoRollView: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                ForEach(0..<numberOfRows, id: \.self) { rowIndex in
                    pianoRollRowView(rowIndex: rowIndex)
                }
            }
        }
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func pianoRollRowView(rowIndex: Int) -> some View {
        let measuresPerLine: Int = beatsPerMeasure > 0 ? (beatsPerRow / beatsPerMeasure) : 0
        
        if measuresPerLine > 0 {
            let firstMeasureInRow = rowIndex * measuresPerLine
            
            GeometryReader { geometry in
                let totalRowWidth = geometry.size.width
                let measureWidth = totalRowWidth / CGFloat(measuresPerLine)
                
                HStack(spacing: 0) {
                    ForEach(0..<measuresPerLine, id: \.self) { measureInRowIndex in
                        let absoluteMeasureIndex = firstMeasureInRow + measureInRowIndex
                        if (absoluteMeasureIndex * beatsPerMeasure) < totalBeats {
                            MeasureView(measureIndex: absoluteMeasureIndex, availableWidth: measureWidth)
                        } else {
                            Color.clear.frame(width: measureWidth)
                        }
                    }
                }
            }
            .frame(height: 50)
        } else {
            EmptyView()
        }
    }

    private func MeasureView(measureIndex: Int, availableWidth: CGFloat) -> some View {
        let firstBeatOfMeasure = measureIndex * beatsPerMeasure
        
        var numContentBeats = 0
        for i in 0..<beatsPerMeasure {
            if appData.sheetMusicBeatMap[firstBeatOfMeasure + i] != nil {
                numContentBeats += 1
            }
        }
        let numEmptyBeats = beatsPerMeasure - numContentBeats
        
        let totalSpacing = CGFloat(beatsPerMeasure > 0 ? beatsPerMeasure - 1 : 0)
        let widthForCells = availableWidth - totalSpacing
        
        let totalWidthUnits = CGFloat(2 * numContentBeats + numEmptyBeats)
        let emptyWidth = totalWidthUnits > 0 ? widthForCells / totalWidthUnits : 0
        let contentWidth = 2 * emptyWidth

        return HStack(spacing: 1) {
            ForEach(0..<beatsPerMeasure, id: \.self) { beatInMeasureIndex in
                let absoluteBeat = firstBeatOfMeasure + beatInMeasureIndex
                if absoluteBeat < totalBeats {
                    let hasContent = appData.sheetMusicBeatMap[absoluteBeat] != nil
                    let cellWidth = hasContent ? contentWidth : emptyWidth
                    pianoRollCell(beat: absoluteBeat, width: cellWidth)
                }
            }
        }
        .frame(width: availableWidth)
    }
    
    private func pianoRollCell(beat: Int, width: CGFloat) -> some View {
        let isSelected = editorState.selectedBeat == beat
        let chordName = appData.sheetMusicBeatMap[beat]
        let hasChord = chordName != nil
        let measurePosition = beat % beatsPerMeasure
        let isBeatOne = measurePosition == 0
        let isHovered = hoveredBeat == beat
        let measureNumber = beat / beatsPerMeasure + 1
        
        let patternIdForBeat = getPatternId(for: beat)
        let isHighlightedByPattern = editorState.highlightedPatternId != nil && patternIdForBeat == editorState.highlightedPatternId
        let isHighlightedByLyric = editorState.highlightedBeats.contains(beat)
        let isAwaitingEndBeat = editorState.lyricTimeRangeStartBeat == beat

        return ZStack {
            // Chord Name in the center
            if let name = chordName {
                Text(MusicTheory.formatChordName(name))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
            }

            // Measure number at the bottom left
            if isBeatOne {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(measureNumber)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding([.leading, .bottom], 3)
                        Spacer()
                    }
                }
            }
        }
        .frame(width: width, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColorForBeat(hasChord: hasChord, isSelected: isSelected, isHovered: isHovered, isBeatOne: isBeatOne, isHighlightedByPattern: isHighlightedByPattern, isHighlightedByLyric: isHighlightedByLyric, isAwaitingEndBeat: isAwaitingEndBeat))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColorForBeat(hasChord: hasChord, isSelected: isSelected, isHovered: isHovered, isBeatOne: isBeatOne, isHighlightedByPattern: isHighlightedByPattern, isHighlightedByLyric: isHighlightedByLyric, isAwaitingEndBeat: isAwaitingEndBeat),
                       lineWidth: isSelected || isHighlightedByPattern || isHighlightedByLyric || isAwaitingEndBeat ? 2 : 1)
        )
        .onHover { hovering in
            hoveredBeat = hovering ? beat : nil
        }
        .onTapGesture {
            handleBeatTap(beat: beat)
        }
    }
    
    private func getPatternId(for beat: Int) -> String? {
        guard let chordName = appData.sheetMusicBeatMap[beat] else { return nil }
        guard let chordConfig = appData.performanceConfig.chords.first(where: { $0.name == chordName }) else { return nil }

        for (_, association) in chordConfig.patternAssociations {
            if let beatIndices = association.beatIndices, beatIndices.contains(beat) {
                return association.patternId
            }
        }
        return nil
    }
    
    private func backgroundColorForBeat(hasChord: Bool, isSelected: Bool, isHovered: Bool, isBeatOne: Bool, isHighlightedByPattern: Bool, isHighlightedByLyric: Bool, isAwaitingEndBeat: Bool) -> Color {
        if isSelected {
            return .accentColor.opacity(0.8)
        }
        if isAwaitingEndBeat {
            return Color.green.opacity(0.6)
        }
        if isHighlightedByLyric {
            return Color.purple.opacity(0.5)
        }
        if isHighlightedByPattern {
            return Color.yellow.opacity(0.5)
        }
        if isHovered {
            return Color.primary.opacity(0.2)
        }
        if isBeatOne {
            return Color.primary.opacity(0.1)
        }
        return Color.primary.opacity(0.05)
    }

    private func borderColorForBeat(hasChord: Bool, isSelected: Bool, isHovered: Bool, isBeatOne: Bool, isHighlightedByPattern: Bool, isHighlightedByLyric: Bool, isAwaitingEndBeat: Bool) -> Color {
        if isSelected {
            return .accentColor
        }
        if isAwaitingEndBeat {
            return Color.green
        }
        if isHighlightedByLyric {
            return Color.purple.opacity(0.9)
        }
        if isHighlightedByPattern {
            return Color.yellow.opacity(0.9)
        }
        if isHovered {
            return Color.primary.opacity(0.5)
        }
        if isBeatOne {
            return Color.primary.opacity(0.4)
        }
        return Color.primary.opacity(0.2)
    }
    
    private var editingControlsView: some View {
        HStack {
            Text("编辑第 \(editorState.selectedBeat ?? 0) 拍")
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Button("取消 (ESC)") {
                finishEditing()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func handleBeatTap(beat: Int) {
        // Check if a lyric is selected
        guard let selectedLyricID = editorState.selectedLyricID else {
            // Original behavior: select beat for chord/pattern editing
            selectBeat(beat)
            return
        }

        var newConfig = appData.performanceConfig
        guard let lyricIndex = newConfig.lyrics.firstIndex(where: { $0.id == selectedLyricID }) else { return }

        // If the tapped beat is the start of an existing range for this lyric, remove it.
        if let rangeIndexToRemove = newConfig.lyrics[lyricIndex].timeRanges.firstIndex(where: { $0.startBeat == beat }) {
            newConfig.lyrics[lyricIndex].timeRanges.remove(at: rangeIndexToRemove)
            appData.performanceConfig = newConfig // Update the main config
            
            updateHighlightedBeatsForSelectedLyric()
            
            // Cancel any pending range creation
            if editorState.lyricTimeRangeStartBeat != nil {
                editorState.lyricTimeRangeStartBeat = nil
            }
            return
        }
        
        // If we are in the process of creating a new range (start beat is set)
        if let startBeat = editorState.lyricTimeRangeStartBeat {
            let newRange = LyricTimeRange(startBeat: min(startBeat, beat), endBeat: max(startBeat, beat))
            newConfig.lyrics[lyricIndex].timeRanges.append(newRange)
            appData.performanceConfig = newConfig // Update the main config
            
            editorState.lyricTimeRangeStartBeat = nil // Reset
            updateHighlightedBeatsForSelectedLyric()
        } else {
            // This is the first tap to define a new range
            editorState.lyricTimeRangeStartBeat = beat
        }
    }

    private func updateHighlightedBeatsForSelectedLyric() {
        DispatchQueue.main.async {
            guard let lyricID = editorState.selectedLyricID,
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
    
    private func selectBeat(_ beat: Int) {
        // Modify local state, not global AppData
        editorState.selectedBeat = beat
        editorState.selectedChordName = nil
        editorState.selectedPatternId = nil
        editorState.highlightedPatternId = nil // Clear highlight when selecting a beat
        editorState.lyricTimeRangeStartBeat = nil // Also clear lyric range selection
    }
    
    private func finishEditing() {
        // Modify local state, not global AppData
        editorState.selectedBeat = nil
        editorState.selectedChordName = nil
        editorState.selectedPatternId = nil
        
        // Switch back to the chords tab
        editorState.activeEditorTab = .chords
    }
    
    private func checkAndAutoApply() {
        // Read from local state
        if let beat = editorState.selectedBeat,
           let chordName = editorState.selectedChordName,
           let patternId = editorState.selectedPatternId {
            
            // This is the point where we "commit" the change to the global AppData
            applySelectionToBeat(beat: beat, chordName: chordName, patternId: patternId)
            
            // Reset local selection state after applying
            finishEditing()
        }
    }
    
    // MARK: - Shortcut Dialog
    
    private var shortcutDialogView: some View {
        ZStack {
            // ... (rest of the file is unchanged)
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelShortcutDialog()
                }
            
            // 对话框内容
            VStack(spacing: 20) {
                Text("设置快捷键")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let data = editorState.shortcutDialogData {
                    VStack(spacing: 12) {
                        Text("为以下组合设置快捷键：")
                            .font(.subheadline)
                        
                        Text("和弦: \(MusicTheory.formatChordName(data.chordName))")
                            .font(.headline)
                        
                        Text("指法: \(data.patternId)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("拍号: \(data.beat)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Divider()
                
                VStack(spacing: 12) {
                    if capturingShortcut {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("请按下快捷键...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("按 ESC 取消")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button("开始捕获快捷键") {
                            startCapturingShortcut()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                HStack {
                    Button("取消") {
                        cancelShortcutDialog()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: 400)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
    
    private func applySelectionToBeat(beat: Int, chordName: String, patternId: String) {
        guard let chordIndex = appData.performanceConfig.chords.firstIndex(where: { $0.name == chordName }) else { return }
        
        let existingShortcut = findExistingShortcut(chordName: chordName, patternId: patternId)
        
        if let shortcut = existingShortcut {
            addBeatToAssociation(chordIndex: chordIndex, shortcut: shortcut, beat: beat)
        } else {
            requestShortcutForCombination(chordIndex: chordIndex, chordName: chordName, patternId: patternId, beat: beat)
        }
    }
    
    private func findExistingShortcut(chordName: String, patternId: String) -> Shortcut? {
        guard let chordConfig = appData.performanceConfig.chords.first(where: { $0.name == chordName }) else {
            return nil
        }
        
        for (shortcut, association) in chordConfig.patternAssociations {
            if association.patternId == patternId {
                return shortcut
            }
        }
        return nil
    }
    
    private func addBeatToAssociation(chordIndex: Int, shortcut: Shortcut, beat: Int) {
        guard var association = appData.performanceConfig.chords[chordIndex].patternAssociations[shortcut] else { return }
        
        if association.beatIndices == nil {
            association.beatIndices = []
        }
        
        if let currentIndices = association.beatIndices, !currentIndices.contains(beat) {
            association.beatIndices?.append(beat)
            association.beatIndices?.sort()
            
            // 使用专用的更新方法
            appData.updateChordPatternAssociation(chordIndex: chordIndex, shortcut: shortcut, association: association)
        }
    }
    
    private func requestShortcutForCombination(chordIndex: Int, chordName: String, patternId: String, beat: Int) {
        // 显示快捷键设置对话框
        editorState.shortcutDialogData = ShortcutDialogData(
            chordName: chordName,
            patternId: patternId,
            beat: beat,
            chordIndex: chordIndex,
            onComplete: { shortcut in
                // 成功设置快捷键后的回调
                finishEditing()
            },
            onCancel: {
                // 用户取消设置快捷键
                finishEditing()
            }
        )
        editorState.showShortcutDialog = true
    }
    
    // MARK: - Shortcut Dialog Methods
    
    private func startCapturingShortcut() {
        guard !capturingShortcut else { return }
        
        capturingShortcut = true
        keyboardHandler.pauseEventMonitoring()
        
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                self.cancelShortcutDialog()
                return nil
            }
            
            if let shortcut = Shortcut.from(event: event) {
                self.handleShortcutInput(shortcut)
            }
            
            return nil
        }
    }
    
    private func handleShortcutInput(_ shortcut: Shortcut) {
        cleanupCaptureMonitor()
        
        // 检查快捷键冲突
        let conflicts = PresetManager.shared.detectConflicts(
            for: shortcut,
            of: editorState.shortcutDialogData?.chordName ?? "",
            in: appData.performanceConfig
        )
        
        if !conflicts.isEmpty {
            conflictMessage = conflicts.map { $0.description }.joined(separator: "\n")
            showConflictAlert = true
        } else {
            // 无冲突，应用快捷键
            applyShortcut(shortcut)
        }
    }
    
    private func applyShortcut(_ shortcut: Shortcut) {
        guard let data = editorState.shortcutDialogData else { return }
        
        let newAssociation = PatternAssociation(patternId: data.patternId, beatIndices: [data.beat])
        appData.addChordPatternAssociation(chordIndex: data.chordIndex, shortcut: shortcut, association: newAssociation)
        
        // 完成回调
        data.onComplete(shortcut)
        
        // 关闭对话框
        closeShortcutDialog()
    }
    
    private func cancelShortcutDialog() {
        cleanupCaptureMonitor()
        editorState.shortcutDialogData?.onCancel()
        closeShortcutDialog()
    }
    
    private func closeShortcutDialog() {
        editorState.showShortcutDialog = false
        editorState.shortcutDialogData = nil
    }
    
    private func cleanupCaptureMonitor() {
        if let monitor = captureMonitor {
            NSEvent.removeMonitor(monitor)
            captureMonitor = nil
        }
        if capturingShortcut {
            capturingShortcut = false
        }
        keyboardHandler.resumeEventMonitoring()
    }
}
