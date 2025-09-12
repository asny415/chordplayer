

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
    
    private let beatsPerRow = 16 // 每行显示16拍，类似钢琴卷粗
    
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
        .onChange(of: appData.performanceConfig.chords) { _ in recalculateTotalBeats() }
        .onDisappear(perform: cleanupCaptureMonitor)
        // When selections from the sidebar change, trigger the auto-apply logic.
        .onChange(of: editorState.selectedChordName) { _ in checkAndAutoApply() }
        .onChange(of: editorState.selectedPatternId) { _ in checkAndAutoApply() }
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
            
            if let beat = editorState.selectedBeat {
                Text("编辑第 \(beat) 拍")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("完成编辑") {
                    finishEditing()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
    
    private var pianoRollView: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 2) {
                ForEach(0..<numberOfRows, id: \.self) {
 rowIndex in
                    pianoRollRowView(rowIndex: rowIndex)
                }
            }
        }
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func pianoRollRowView(rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            
            
            // 钢琴卷粗格子
            GeometryReader { geometry in
                let totalSpacing = CGFloat(beatsPerRow - 1) * 1 // 1pt spacing between cells
                let cellWidth = (geometry.size.width - totalSpacing) / CGFloat(beatsPerRow)
                
                HStack(spacing: 1) {
                    ForEach(0..<beatsPerRow, id: \.self) { beatInRow in
                        let absoluteBeat = rowIndex * beatsPerRow + beatInRow
                        if absoluteBeat < totalBeats {
                            pianoRollCell(beat: absoluteBeat, width: cellWidth)
                        }
                    }
                }
            }
        }
        .frame(height: 50)
    }
    
    private func pianoRollCell(beat: Int, width: CGFloat) -> some View {
        let isSelected = editorState.selectedBeat == beat
        let chordName = appData.sheetMusicBeatMap[beat]
        let hasChord = chordName != nil
        let measurePosition = beat % beatsPerMeasure
        let isBeatOne = measurePosition == 0
        let isHovered = hoveredBeat == beat
        let measureNumber = beat / beatsPerMeasure + 1

        return ZStack {
            // Chord Name in the center
            if let name = chordName {
                Text(formatChordName(name))
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
                .fill(backgroundColorForBeat(hasChord: hasChord, isSelected: isSelected, isHovered: isHovered, isBeatOne: isBeatOne))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColorForBeat(hasChord: hasChord, isSelected: isSelected, isHovered: isHovered, isBeatOne: isBeatOne),
                       lineWidth: isSelected ? 2 : 1)
        )
        .onHover { hovering in
            hoveredBeat = hovering ? beat : nil
        }
        .onTapGesture {
            selectBeat(beat)
        }
    }
    
    private func backgroundColorForBeat(hasChord: Bool, isSelected: Bool, isHovered: Bool, isBeatOne: Bool) -> Color {
        if isSelected {
            return .accentColor.opacity(0.8)
        }
        if isHovered {
            return Color.primary.opacity(0.2)
        }
        if isBeatOne {
            return Color.primary.opacity(0.1)
        }
        return Color.primary.opacity(0.05)
    }

    private func borderColorForBeat(hasChord: Bool, isSelected: Bool, isHovered: Bool, isBeatOne: Bool) -> Color {
        if isSelected {
            return .accentColor
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
    
    private func selectBeat(_ beat: Int) {
        // Modify local state, not global AppData
        editorState.selectedBeat = beat
        editorState.selectedChordName = nil
        editorState.selectedPatternId = nil
    }
    
    private func finishEditing() {
        // Modify local state, not global AppData
        editorState.selectedBeat = nil
        editorState.selectedChordName = nil
        editorState.selectedPatternId = nil
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
    
    
    
    private func formatChordName(_ chordName: String) -> String {
        return chordName.replacingOccurrences(of: "_Sharp", with: "#")
                       .replacingOccurrences(of: "_", with: " ")
    }
    
    // MARK: - Shortcut Dialog
    
    private var shortcutDialogView: some View {
        ZStack {
            // 半透明背景
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
                
                if let data = appData.shortcutDialogData {
                    VStack(spacing: 12) {
                        Text("为以下组合设置快捷键：")
                            .font(.subheadline)
                        
                        Text("和弦: \(formatChordName(data.chordName))")
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
        appData.shortcutDialogData = ShortcutDialogData(
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
        appData.showShortcutDialog = true
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
            of: appData.shortcutDialogData?.chordName ?? "",
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
        guard let data = appData.shortcutDialogData else { return }
        
        let newAssociation = PatternAssociation(patternId: data.patternId, beatIndices: [data.beat])
        appData.addChordPatternAssociation(chordIndex: data.chordIndex, shortcut: shortcut, association: newAssociation)
        
        // 完成回调
        data.onComplete(shortcut)
        
        // 关闭对话框
        closeShortcutDialog()
    }
    
    private func cancelShortcutDialog() {
        cleanupCaptureMonitor()
        appData.shortcutDialogData?.onCancel()
        closeShortcutDialog()
    }
    
    private func closeShortcutDialog() {
        appData.showShortcutDialog = false
        appData.shortcutDialogData = nil
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
