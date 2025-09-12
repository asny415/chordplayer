
import SwiftUI

struct PlayingPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager

    @State private var showAddPlayingPatternSheet: Bool = false
    @State private var isHoveringGroup: Bool = false

    var body: some View {
        let _ = print("[DEBUG] PlayingPatternsView.body render start")
        VStack(alignment: .leading) {
            HStack {
                Text("和弦指法").font(.headline)
                Spacer()

                // Add Pattern to Workspace Button
                Button(action: { showAddPlayingPatternSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .help("从库添加演奏模式到工作区")
            }
            if appData.performanceConfig.selectedPlayingPatterns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("当前没有和弦指法。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加和弦指法，或使用数字键 1/2... 快速选择")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(Array(appData.performanceConfig.selectedPlayingPatterns.enumerated()), id: \.element) { index, patternId in
                        if let details = findPlayingPatternDetails(for: patternId) {
                            let isActive = appData.performanceConfig.activePlayingPatternId == patternId
                            let isEditingSelected = appData.sheetMusicEditingBeat != nil && appData.sheetMusicSelectedPatternId == patternId
                            Button(action: {
                                if appData.sheetMusicEditingBeat != nil {
                                    // 曲谱编辑模式：选择演奏指法
                                    appData.sheetMusicSelectedPatternId = patternId
                                    checkAndAutoApply()
                                } else {
                                    // 普通模式：设置活动指法
                                    appData.performanceConfig.activePlayingPatternId = patternId
                                }
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    PlayingPatternCardView(
                                        index: index,
                                        pattern: details.pattern,
                                        category: details.category,
                                        timeSignature: appData.performanceConfig.timeSignature,
                                        isActive: isActive,
                                        isEditingSelected: isEditingSelected
                                    )

                                    if index < 9 {
                                        Text("\(index + 1)")
                                            .font(.caption2).bold()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                            .offset(x: -8, y: 8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: appData.performanceConfig.activePlayingPatternId)
                            .contextMenu {
                                Button(role: .destructive) {
                                    appData.removePlayingPattern(patternId: patternId)
                                } label: {
                                    Label("移除指法", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringGroup = hovering
            }
        }
        .sheet(isPresented: $showAddPlayingPatternSheet) {
            AddPlayingPatternSheetView()
        }
    }
    
    private func findPlayingPatternDetails(for patternId: String) -> (pattern: GuitarPattern, category: String)? {
        // Search in custom patterns first
        for (_, patterns) in customPlayingPatternManager.customPlayingPatterns {
            if let pattern = patterns.first(where: { $0.id == patternId }) {
                return (pattern, "自定义")
            }
        }
        
        // Then search in system patterns
        if let library = appData.patternLibrary {
            for (category, patterns) in library {
                if let pattern = patterns.first(where: { $0.id == patternId }) {
                    return (pattern, category)
                }
            }
        }
        
        return nil
    }
    
    private func checkAndAutoApply() {
        // 只有在两者都选择了才自动应用
        if appData.sheetMusicSelectedChordName != nil && appData.sheetMusicSelectedPatternId != nil {
            // 直接调用SheetMusicEditorView的逻辑，但我们需要在这里实现
            if let beat = appData.sheetMusicEditingBeat,
               let chordName = appData.sheetMusicSelectedChordName,
               let patternId = appData.sheetMusicSelectedPatternId {
                
                // 查找对应的和弦配置
                guard let chordIndex = appData.performanceConfig.chords.firstIndex(where: { $0.name == chordName }) else {
                    return
                }
                
                // 检查是否已经存在这个组合的快捷键
                let existingShortcut = findExistingShortcut(chordName: chordName, patternId: patternId)
                
                if let shortcut = existingShortcut {
                    // 已经存在快捷键，直接添加beat到beatIndices
                    addBeatToAssociation(chordIndex: chordIndex, shortcut: shortcut, beat: beat)
                    finishEditing()
                } else {
                    // 不存在快捷键，需要用户指定
                    requestShortcutForCombination(chordIndex: chordIndex, chordName: chordName, patternId: patternId, beat: beat)
                }
            }
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
                self.finishEditing()
            },
            onCancel: {
                // 用户取消设置快捷键
                self.finishEditing()
            }
        )
        appData.showShortcutDialog = true
    }
    
    private func finishEditing() {
        appData.sheetMusicEditingBeat = nil
        appData.sheetMusicSelectedChordName = nil
        appData.sheetMusicSelectedPatternId = nil
    }
}

struct PlayingPatternCardView: View {
    let index: Int
    let pattern: GuitarPattern
    let category: String
    let timeSignature: String
    let isActive: Bool
    let isEditingSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlayingPatternView(
                pattern: pattern,
                timeSignature: timeSignature,
                color: isActive ? .accentColor : .primary
            )
            .opacity(isActive ? 1.0 : 0.7)
            .padding(.bottom, 4)
            .padding(.trailing, 35)

            HStack {
                Text(pattern.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            HStack {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .foregroundColor(.primary)
        .padding(8)
        .frame(width: 140, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isEditingSelected ? Color.orange : (isActive ? Color.accentColor : Color.secondary.opacity(0.2)), 
                       lineWidth: isEditingSelected ? 3 : (isActive ? 2.5 : 1))
        )
    }
}
