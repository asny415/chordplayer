import SwiftUI

struct AddChordPlayingPatternAssociationSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    let chordName: String
    
    @State private var selectedPlayingPatternId: String?
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any? = nil
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    
    private var availablePlayingPatterns: [GuitarPattern] {
        let timeSignature = appData.performanceConfig.timeSignature
        var patterns: [GuitarPattern] = []
        
        if let library = appData.patternLibrary?[timeSignature] {
            patterns.append(contentsOf: library)
        }
        
        if let customLibrary = CustomPlayingPatternManager.shared.customPlayingPatterns[timeSignature] {
            patterns.append(contentsOf: customLibrary)
        }
        
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
                Text("1. 选择演奏指法")
                    .font(.headline)
                
                if availablePlayingPatterns.isEmpty {
                    Text("当前没有可用的演奏指法。请先在工作区中添加演奏指法。")
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 10) {
                            ForEach(availablePlayingPatterns, id: \.id) { pattern in
                                Button(action: { selectedPlayingPatternId = pattern.id }) {
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
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("2. 设置快捷键")
                    .font(.headline)
                
                Button(action: startCapturingShortcut) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text(capturingShortcut ? "请按下快捷键... (Esc 取消)" : "点击设置快捷键")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(capturingShortcut ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(selectedPlayingPatternId == nil)
            }
            
            Spacer()
            
            HStack {
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 500)
        .alert("快捷键冲突", isPresented: $showConflictAlert) {
            Button("确定") { }
        } message: {
            Text(conflictMessage)
        }
        .onDisappear(perform: cleanupCaptureMonitor)
    }
    
    private func startCapturingShortcut() {
        guard !capturingShortcut else { return }
        
        capturingShortcut = true
        keyboardHandler.pauseEventMonitoring()
        
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                self.cleanupCaptureMonitor()
                return nil
            }
            
            if let shortcut = Shortcut.from(event: event) {
                let conflicts = PresetManager.shared.detectConflicts(
                    for: shortcut,
                    of: self.chordName,
                    in: self.appData.performanceConfig
                )
                
                if !conflicts.isEmpty {
                    self.conflictMessage = conflicts.map { $0.description }.joined(separator: "\n")
                    self.showConflictAlert = true
                } else {
                    self.saveAssociation(with: shortcut)
                    self.dismiss()
                }
            }
            
            self.cleanupCaptureMonitor()
            return nil
        }
    }
    
    private func saveAssociation(with shortcut: Shortcut) {
        guard let patternId = selectedPlayingPatternId else { return }
        
        if let index = appData.performanceConfig.chords.firstIndex(where: { $0.name == chordName }) {
            appData.performanceConfig.chords[index].patternAssociations[shortcut] = patternId
            print("✅ Associated shortcut '\(shortcut.stringValue)' with pattern '\(patternId)' for chord '\(chordName)'")
        }
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
