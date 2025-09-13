
import SwiftUI

struct ChordProgressionView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var flashingChord: String? = nil
    @State private var showAddChordSheet: Bool = false
    @State private var capturingChord: String? = nil
    @State private var captureMonitor: Any? = nil
    @State private var isHoveringGroup: Bool = false
    @State private var badgeHoveredForChord: String? = nil
    

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("和弦进行").font(.headline)
                Spacer()
                Button(action: { showAddChordSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
            }
            
            if appData.performanceConfig.chords.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("当前没有和弦进行。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加和弦，或在和弦库中选择并添加到进行中。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(appData.performanceConfig.chords, id: \.id) { chordConfig in
                        let isEditingSelected = appData.sheetMusicEditingBeat != nil && appData.sheetMusicSelectedChordName == chordConfig.name
                        ZStack(alignment: .topTrailing) {
                            ChordCardView(chord: chordConfig.name, 
                                         isFlashing: flashingChord == chordConfig.name, 
                                         isEditingSelected: isEditingSelected)
                                .animation(.easeInOut(duration: 0.15), value: flashingChord)
                                .onTapGesture {
                                    if appData.sheetMusicEditingBeat != nil {
                                        // 曲谱编辑模式：选择和弦
                                        appData.sheetMusicSelectedChordName = chordConfig.name
                                        checkAndAutoApply()
                                    } else {
                                        // 普通模式：播放和弦
                                        keyboardHandler.playChordByName(chordConfig.name)
                                    }
                                }

                            // Shortcut badge (custom or default). Always show a Text badge.
                            let (baseBadgeText, baseBadgeColor): (String, Color) = {
                                // 1) user-assigned shortcut
                                if let shortcutValue = chordConfig.shortcut, let s = Shortcut(stringValue: shortcutValue) {
                                    return (s.displayText, Color.accentColor)
                                }

                                // 2) fallback to sensible default mapping for simple single-letter notes
                                let components = chordConfig.name.split(separator: "_")
                                if components.count >= 2 {
                                    let quality = String(components.last!)
                                    let noteParts = components.dropLast()
                                    let noteRaw = noteParts.joined(separator: "_")
                                    let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")

                                    if noteDisplay.count == 1 {
                                        if quality == "Major" {
                                            return (noteDisplay.uppercased(), Color.gray.opacity(0.6))
                                        } else if quality == "Minor" {
                                            return ("⇧\(noteDisplay.uppercased())", Color.gray.opacity(0.6))
                                        }
                                    }
                                }

                                // 3) otherwise show a marker indicating the user can set a shortcut
                                // 使用单字标记以保持徽章简洁（假设为中文环境，使用“设”表示“设置快捷键”）
                                return ("+", Color.gray.opacity(0.6))
                            }()
                            
                            let isBadgeHovered = badgeHoveredForChord == chordConfig.name
                            let badgeText = baseBadgeText
                            let badgeColor = isBadgeHovered ? baseBadgeColor.opacity(0.7) : baseBadgeColor


                            // Badge button: tapping this starts capturing a new shortcut for this chord.
                            Button(action: {
                                captureShortcutForChord(chord: chordConfig.name)
                            }) {
                                Text(badgeText)
                                    .font(.caption2).bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation {
                                    badgeHoveredForChord = hovering ? chordConfig.name : nil
                                }
                            }
                            .help("编辑快捷键")
                            .offset(x: -8, y: 8)
                        }
                        // Bottom-right badges for associated playing pattern shortcuts
                        .overlay(alignment: .bottomTrailing) {
                            let shortcuts = sortedPatternShortcuts(for: chordConfig)
                            if !shortcuts.isEmpty {
                                HStack(spacing: 6) {
                                    let maxShow = 3
                                    let shown = Array(shortcuts.prefix(maxShow))
                                    let rest = shortcuts.count > maxShow ? Array(shortcuts.dropFirst(maxShow)) : []
                                    ForEach(shown, id: \.stringValue) { sc in
                                        Text(sc.displayText)
                                            .font(.caption2).bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.15), in: Capsule())
                                    }
                                    if !rest.isEmpty {
                                        Text("+\(rest.count)")
                                            .font(.caption2).bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.12), in: Capsule())
                                            .help(rest.map { $0.displayText }.joined(separator: ", "))
                                    }
                                }
                                .padding(6)
                                .allowsHitTesting(false) // avoid intercepting the tap on the chord card
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                appData.removeChord(chordName: chordConfig.name)
                            } label: {
                                Label("移除和弦", systemImage: "trash")
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
        .overlay(
            Group {
                if capturingChord != nil {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 12) {
                            Text("Press a key to assign shortcut")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Press Esc to cancel")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(24)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity)
                }
            }
        )

        .onReceive(keyboardHandler.$lastPlayedChord) { chord in
            guard let chord = chord else { return }
            flashingChord = chord
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                flashingChord = nil
            }
        }
        .sheet(isPresented: $showAddChordSheet) {
            ChordLibraryView(onAddChord: { chordName in
                appData.performanceConfig.chords.append(ChordPerformanceConfig(name: chordName))
            }, existingChordNames: Set(appData.performanceConfig.chords.map { $0.name }))
        }
        
    }

    // MARK: - Helpers for sorting pattern association shortcuts
    private func sortedPatternShortcuts(for chordConfig: ChordPerformanceConfig) -> [Shortcut] {
        let shortcuts = chordConfig.patternAssociations.keys.map { $0 }
        return shortcuts.sorted(by: shortcutSortLessThan(_:_:))
    }
    
    private func shortcutSortLessThan(_ a: Shortcut, _ b: Shortcut) -> Bool {
        // Weight modifiers: cmd > ctrl > opt > shift
        func weight(_ s: Shortcut) -> Int {
            var w = 0
            if s.modifiersCommand { w += 8 }
            if s.modifiersControl { w += 4 }
            if s.modifiersOption { w += 2 }
            if s.modifiersShift { w += 1 }
            return w
        }
        let wa = weight(a)
        let wb = weight(b)
        if wa != wb { return wa > wb }
        // Then by key lexicographically
        return a.key < b.key
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

    private func captureShortcutForChord(chord: String) {
        // start capturing
        capturingChord = chord
        // Temporarily pause the global keyboard handler so it doesn't intercept
        // the key event we're trying to capture.
        keyboardHandler.pauseEventMonitoring()

        // add local monitor to capture next keyDown
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape key to cancel
            if event.keyCode == 53 {
                if let m = captureMonitor { NSEvent.removeMonitor(m) }
                captureMonitor = nil
                capturingChord = nil
                // restore global handler
                keyboardHandler.resumeEventMonitoring()
                return nil
            }

            if let s = Shortcut.from(event: event) {
                PresetManager.shared.setShortcut(s, forChord: chord)
            }

            if let m = captureMonitor { NSEvent.removeMonitor(m) }
            captureMonitor = nil
            capturingChord = nil
            // restore global handler
            keyboardHandler.resumeEventMonitoring()
            return nil
        }
    }
}

struct ChordCardView: View {
    @EnvironmentObject var appData: AppData
    let chord: String
    let isFlashing: Bool
    let isEditingSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main content - chord name
            VStack(alignment: .center) {
                Text(MusicTheory.formatChordName(chord))
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(.primary)
            .frame(width: 140, height: 80)
            .background(isFlashing ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEditingSelected ? Color.orange : (isFlashing ? Color.accentColor : Color.secondary.opacity(0.2)), 
                           lineWidth: isEditingSelected ? 3 : (isFlashing ? 2.5 : 1))
            )

            // Chord diagram in the bottom-left corner
            if let frets = appData.chordLibrary?[chord] {
                ChordDiagramView(frets: frets, color: .primary.opacity(0.8))
                    .frame(width: 40, height: 48)
                    .padding(6)
            }
        }
    }

    
}
