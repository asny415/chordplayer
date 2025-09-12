

import SwiftUI
import AppKit

struct GlobalShortcutDialogView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    // 快捷键对话框状态
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any? = nil
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    
    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.5)
                .ignoresSafeArea(.all)
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
                        
                        Text("和弦: \(MusicTheory.formatChordNameForDisplay(data.chordName))")
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
        .alert("快捷键冲突", isPresented: $showConflictAlert) {
            Button("确定") { }
        } message: {
            Text(conflictMessage)
        }
        .onAppear {
            // 对话框出现时立即开始捕获快捷键
            startCapturingShortcut()
        }
        .onDisappear(perform: cleanupCaptureMonitor)
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

