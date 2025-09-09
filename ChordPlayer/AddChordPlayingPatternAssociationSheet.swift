import SwiftUI

struct AddChordPlayingPatternAssociationSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    let chordName: String
    
    @State private var selectedPlayingPatternId: String?
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any?
    @State private var conflicts: [ShortcutConflict] = []
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    
    private var availablePlayingPatterns: [GuitarPattern] {
        let timeSignature = appData.performanceConfig.timeSignature
        var patterns: [GuitarPattern] = []
        
        // 添加内置演奏指法
        if let library = appData.patternLibrary?[timeSignature] {
            patterns.append(contentsOf: library)
        }
        
        // 添加自定义演奏指法
        if let customLibrary = CustomPlayingPatternManager.shared.customPlayingPatterns[timeSignature] {
            patterns.append(contentsOf: customLibrary)
        }
        
        // 只返回已选中的演奏指法
        return patterns.filter { appData.performanceConfig.selectedPlayingPatterns.contains($0.id) }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("添加演奏指法关联")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("为和弦 \(chordName.replacingOccurrences(of: "_", with: " ")) 关联演奏指法")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("选择演奏指法")
                    .font(.headline)
                
                if availablePlayingPatterns.isEmpty {
                    Text("当前没有可用的演奏指法。请先在工作区中添加演奏指法。")
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 10) {
                        ForEach(availablePlayingPatterns, id: \.id) { pattern in
                            Button(action: {
                                selectedPlayingPatternId = pattern.id
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    PlayingPatternView(
                                        pattern: pattern,
                                        timeSignature: appData.performanceConfig.timeSignature,
                                        color: selectedPlayingPatternId == pattern.id ? .accentColor : .primary
                                    )
                                    .frame(height: 60)
                                    
                                    Text(pattern.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedPlayingPatternId == pattern.id ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedPlayingPatternId == pattern.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if let selectedId = selectedPlayingPatternId {
                VStack(alignment: .leading, spacing: 12) {
                    Text("设置快捷键")
                        .font(.headline)
                    
                    if capturingShortcut {
                        VStack(spacing: 8) {
                            Text("请按下快捷键...")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                            Text("按 Esc 取消")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Button(action: startCapturingShortcut) {
                            HStack {
                                Image(systemName: "keyboard")
                                Text("点击设置快捷键")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("完成") {
                    if let patternId = selectedPlayingPatternId {
                        // 这里需要从captureMonitor获取快捷键
                        // 暂时使用一个占位符，实际实现需要从captureMonitor获取
                        let shortcut = Shortcut(key: "A", modifiersShift: false)
                        let success = PresetManager.shared.addChordPlayingPatternAssociation(
                            chordName: chordName,
                            playingPatternId: patternId,
                            shortcut: shortcut
                        )
                        if success {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlayingPatternId == nil || capturingShortcut)
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
        .alert("快捷键冲突", isPresented: $showConflictAlert) {
            Button("确定") { }
        } message: {
            Text(conflictMessage)
        }
        .onDisappear {
            cleanupCaptureMonitor()
        }
    }
    
    private func startCapturingShortcut() {
        capturingShortcut = true
        keyboardHandler.pauseEventMonitoring()
        
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape key to cancel
            if event.keyCode == 53 {
                cleanupCaptureMonitor()
                return nil
            }
            
            if let shortcut = Shortcut.from(event: event) {
                // 检查冲突
                let conflicts = PresetManager.shared.detectShortcutConflicts(shortcut, for: chordName)
                if !conflicts.isEmpty {
                    conflictMessage = conflicts.map { $0.description }.joined(separator: "\n")
                    showConflictAlert = true
                } else {
                    // 添加关联
                    if let patternId = selectedPlayingPatternId {
                        let success = PresetManager.shared.addChordPlayingPatternAssociation(
                            chordName: chordName,
                            playingPatternId: patternId,
                            shortcut: shortcut
                        )
                        if success {
                            dismiss()
                        }
                    }
                }
            }
            
            cleanupCaptureMonitor()
            return nil
        }
    }
    
    private func cleanupCaptureMonitor() {
        if let monitor = captureMonitor {
            NSEvent.removeMonitor(monitor)
            captureMonitor = nil
        }
        capturingShortcut = false
        keyboardHandler.resumeEventMonitoring()
    }
}
