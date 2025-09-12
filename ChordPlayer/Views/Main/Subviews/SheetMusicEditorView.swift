

import SwiftUI
import AppKit

struct SheetMusicEditorView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    // 快捷键对话框状态
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any? = nil
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    
    private var beatsPerMeasure: Int {
        let timeSigParts = appData.performanceConfig.timeSignature.split(separator: "/")
        return Int(timeSigParts.first.map(String.init) ?? "4") ?? 4
    }
    
    // 自动长度：总节拍数+1小节（直接从配置计算，而非autoPlaySchedule）
    private var totalBeats: Int {
        let currentMaxBeat = getCurrentMaxBeatFromConfig()
        
        if currentMaxBeat < 0 {
            // 没有任何数据，默认4小节 + 1额外小节 = 5小节
            return 5 * beatsPerMeasure
        }
        
        // 计算当前最大拍号所在的小节数（从1开始）
        let maxMeasureNumber = (currentMaxBeat / beatsPerMeasure) + 1
        
        // 总小节数 = 最大小节数 + 1额外小节
        return (maxMeasureNumber + 1) * beatsPerMeasure
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
    
    private let beatsPerRow = 16 // 每行显示16拍，类似钢琴卷粗
    
    private var numberOfRows: Int {
        return Int(ceil(Double(totalBeats) / Double(beatsPerRow)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            pianoRollView
            if appData.sheetMusicEditingBeat != nil {
                editingControlsView
            }
        }
        .padding()
        .alert("快捷键冲突", isPresented: $showConflictAlert) {
            Button("确定") { }
        } message: {
            Text(conflictMessage)
        }
        .onDisappear(perform: cleanupCaptureMonitor)
    }
    
    private var headerView: some View {
        HStack {
            Text("曲谱编辑")
                .font(.headline)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                let currentMaxBeat = getCurrentMaxBeatFromConfig()
                let maxMeasure = currentMaxBeat < 0 ? 0 : (currentMaxBeat / beatsPerMeasure) + 1
                let totalMeasures = (maxMeasure == 0 ? 4 : maxMeasure) + 1
                
                Text("最大小节: \(maxMeasure) | 总长度: \(totalMeasures)小节")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("总拍数: \(totalBeats)")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            if let beat = appData.sheetMusicEditingBeat {
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
            // 行号标签
            Text("\(rowIndex * beatsPerRow)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
                .padding(.trailing, 4)
            
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
        let isSelected = appData.sheetMusicEditingBeat == beat
        let chordName = appData.sheetMusicBeatMap[beat]
        let hasChord = chordName != nil
        let measurePosition = beat % beatsPerMeasure
        let isBeatOne = measurePosition == 0
        
        return Button(action: {
            selectBeat(beat)
        }) {
            VStack(spacing: 2) {
                // 和弦名称显示
                if let name = chordName {
                    Text(formatChordName(name))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                // 拍号
                Text("\(beat)")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(width: width, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(backgroundColorForBeat(beat: beat, hasChord: hasChord, isSelected: isSelected, isBeatOne: isBeatOne))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(borderColorForBeat(beat: beat, hasChord: hasChord, isSelected: isSelected, isBeatOne: isBeatOne), 
                       lineWidth: isSelected ? 2 : (isBeatOne ? 1.5 : 0.5))
        )
    }
    
    private func backgroundColorForBeat(beat: Int, hasChord: Bool, isSelected: Bool, isBeatOne: Bool) -> Color {
        if isSelected {
            return .accentColor.opacity(0.4)
        } else if hasChord {
            return .green.opacity(0.3)
        } else if isBeatOne {
            return .blue.opacity(0.1) // 每小节第一拍用蓝色
        } else {
            return .primary.opacity(0.05)
        }
    }
    
    private func borderColorForBeat(beat: Int, hasChord: Bool, isSelected: Bool, isBeatOne: Bool) -> Color {
        if isSelected {
            return .accentColor
        } else if hasChord {
            return .green.opacity(0.8)
        } else if isBeatOne {
            return .blue.opacity(0.5)
        } else {
            return .primary.opacity(0.2)
        }
    }
    
    private var editingControlsView: some View {
        HStack {
            Text("编辑第 \(appData.sheetMusicEditingBeat ?? 0) 拍")
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
        appData.sheetMusicEditingBeat = beat
        appData.sheetMusicSelectedChordName = nil
        appData.sheetMusicSelectedPatternId = nil
    }
    
    private func finishEditing() {
        appData.sheetMusicEditingBeat = nil
        appData.sheetMusicSelectedChordName = nil
        appData.sheetMusicSelectedPatternId = nil
    }
    
    // 自动检查并应用选择
    private func checkAndAutoApply() {
        // 只有在两者都选择了才自动应用
        if appData.sheetMusicSelectedChordName != nil && appData.sheetMusicSelectedPatternId != nil {
            applySelectionToBeat()
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
    
    private func applySelectionToBeat() {
        guard let beat = appData.sheetMusicEditingBeat,
              let chordName = appData.sheetMusicSelectedChordName,
              let patternId = appData.sheetMusicSelectedPatternId else { return }
        
        // 查找对应的和弦配置
        guard let chordIndex = appData.performanceConfig.chords.firstIndex(where: { $0.name == chordName }) else {
            return
        }
        
        // 检查是否已经存在这个组合的快捷键
        let existingShortcut = findExistingShortcut(chordName: chordName, patternId: patternId)
        
        if let shortcut = existingShortcut {
            // 已经存在快捷键，直接添加beat到beatIndices
            addBeatToAssociation(chordIndex: chordIndex, shortcut: shortcut, beat: beat)
        } else {
            // 不存在快捷键，需要用户指定
            requestShortcutForCombination(chordIndex: chordIndex, chordName: chordName, patternId: patternId, beat: beat)
        }
        
        finishEditing()
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
