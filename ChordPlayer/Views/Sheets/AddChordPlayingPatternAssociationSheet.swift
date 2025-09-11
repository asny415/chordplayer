import SwiftUI

// MARK: - Main View

struct AddChordPlayingPatternAssociationSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    
    let chordName: String
    
    // MARK: - State
    @State private var selectedPlayingPatternId: String?
    @State private var capturingShortcut: Bool = false
    @State private var captureMonitor: Any? = nil
    @State private var showConflictAlert: Bool = false
    @State private var conflictMessage: String = ""
    @State private var infoMessage: String? = nil
    
    // State for popover
    @State private var editingAssociationId: String?
    
    private var availablePlayingPatterns: [GuitarPattern] {
        let timeSignature = appData.performanceConfig.timeSignature
        var patterns: [GuitarPattern] = []
        
        if let library = appData.patternLibrary?[timeSignature] {
            patterns.append(contentsOf: library)
        }
        
        if let customLibrary = customPlayingPatternManager.customPlayingPatterns[timeSignature] {
            patterns.append(contentsOf: customLibrary)
        }
        
        return patterns.filter { appData.performanceConfig.selectedPlayingPatterns.contains($0.id) }
    }
    
    private var chordConfigIndex: Int? {
        appData.performanceConfig.chords.firstIndex(where: { $0.name == chordName })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("管理演奏指法关联")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("为和弦 \(chordName.replacingOccurrences(of: "_", with: " ")) 关联演奏指法")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // 1. Select Pattern
            VStack(alignment: .leading, spacing: 12) {
                Text("1. 选择或编辑指法")
                    .font(.headline)
                
                if availablePlayingPatterns.isEmpty {
                    Text("当前没有可用的演奏指法。请先在工作区中添加演奏指法。")
                        .foregroundColor(.secondary).padding().background(Color.gray.opacity(0.1)).cornerRadius(8)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                            ForEach(availablePlayingPatterns, id: \.id) { pattern in
                                patternCardButton(pattern: pattern)
                            }
                        }
                    }
                }
            }
            
            // 2. Set Shortcut for selected pattern
            VStack(alignment: .leading, spacing: 12) {
                Text("2. 为新指法设置快捷键")
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
                .disabled(selectedPlayingPatternId == nil || isPatternAssociated(patternId: selectedPlayingPatternId))
                
                if let info = infoMessage {
                    HStack(spacing: 8) { Image(systemName: "info.circle"); Text(info) }
                        .font(.caption).foregroundColor(.secondary)
                }
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
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func patternCardButton(pattern: GuitarPattern) -> some View {
        let association = findAssociation(for: pattern.id)
        let isAssociated = association != nil
        let isSelectedForBinding = selectedPlayingPatternId == pattern.id && !isAssociated
        
        Button(action: {
            if isAssociated {
                editingAssociationId = pattern.id
            } else {
                selectedPlayingPatternId = pattern.id
            }
        }) {
            patternCardView(pattern: pattern, association: association, isSelected: isSelectedForBinding)
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { editingAssociationId == pattern.id },
            set: { if !$0 { editingAssociationId = nil } }
        ), arrowEdge: .bottom) {
            if let association = findAssociation(for: pattern.id) {
                MeasureIndexEditorView(
                    patternName: pattern.name,
                    shortcut: association.key,
                    initialIndices: association.value.measureIndices ?? [],
                    onSave: { indices in
                        updateMeasureIndices(for: association.key, newIndices: indices)
                        editingAssociationId = nil
                    },
                    onDeleteAssociation: {
                        removeAssociation(for: association.key)
                        editingAssociationId = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func patternCardView(pattern: GuitarPattern, association: (key: Shortcut, value: PatternAssociation)?, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PlayingPatternView(
                pattern: pattern,
                timeSignature: appData.performanceConfig.timeSignature,
                color: (isSelected || association != nil) ? .accentColor : .primary
            )
            .frame(height: 60)
            
            Text(pattern.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            if let assoc = association {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assoc.key.displayText)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(6)
                    
                    if let indices = assoc.value.measureIndices, !indices.isEmpty {
                        Text("应用小节: \(indices.map { String(format: "%g", $0) }.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : (association != nil ? Color.accentColor.opacity(0.5) : Color.clear), lineWidth: 2)
                )
        )
    }

    // MARK: - Logic
    
    private func findAssociation(for patternId: String) -> (key: Shortcut, value: PatternAssociation)? {
        guard let config = chordConfigIndex.map({ appData.performanceConfig.chords[$0] }) else {
            return nil
        }
        return config.patternAssociations.first(where: { $0.value.patternId == patternId })
    }
    
    private func isPatternAssociated(patternId: String?) -> Bool {
        guard let patternId = patternId else { return false }
        return findAssociation(for: patternId) != nil
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
                    self.infoMessage = "已绑定 \(shortcut.displayText)。"
                }
            }
            
            self.cleanupCaptureMonitor()
            return nil
        }
    }
    
    private func saveAssociation(with shortcut: Shortcut) {
        guard let patternId = selectedPlayingPatternId, let index = chordConfigIndex else { return }
        
        let newAssociation = PatternAssociation(patternId: patternId, measureIndices: nil)
        appData.performanceConfig.chords[index].patternAssociations[shortcut] = newAssociation
        selectedPlayingPatternId = nil // Reset selection
    }
    
    private func removeAssociation(for shortcut: Shortcut) {
        guard let index = chordConfigIndex else { return }
        appData.performanceConfig.chords[index].patternAssociations.removeValue(forKey: shortcut)
    }
    
    private func updateMeasureIndices(for shortcut: Shortcut, newIndices: [Double]) {
        guard let index = chordConfigIndex else { return }
        let sortedIndices = newIndices.sorted()
        appData.performanceConfig.chords[index].patternAssociations[shortcut]?.measureIndices = sortedIndices.isEmpty ? nil : sortedIndices
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


// MARK: - Popover Editor View

private struct MeasureIndexEditorView: View {
    let patternName: String
    let shortcut: Shortcut
    let onSave: ([Double]) -> Void
    let onDeleteAssociation: () -> Void

    @State private var indices: [Double]
    @State private var input: String = ""
    @State private var isInputInvalid: Bool = false

    init(patternName: String, shortcut: Shortcut, initialIndices: [Double], onSave: @escaping ([Double]) -> Void, onDeleteAssociation: @escaping () -> Void) {
        self.patternName = patternName
        self.shortcut = shortcut
        self._indices = State(initialValue: initialIndices)
        self.onSave = onSave
        self.onDeleteAssociation = onDeleteAssociation
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(patternName)
                    .font(.headline)
                Text("快捷键: \(shortcut.displayText)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            tokenFieldView
            
            HStack {
                Button(role: .destructive, action: onDeleteAssociation) {
                    Text("解除关联")
                }
                Spacer()
                Button("完成", action: { onSave(indices) }).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
    
    private var tokenFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("指定应用小节 (如 1, 2.5)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(indices, id: \.self) { index in
                        HStack(spacing: 4) {
                            Text(String(format: "%g", index))
                            Button(action: { removeMeasureIndex(index) }) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(12)
                    }
                    
                    TextField("添加", text: $input)
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                        .padding(.vertical, 4)
                        .onChange(of: input) { newValue in
                            if newValue.contains(",") || newValue.contains(" ") {
                                let processedInput = newValue.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                                addMeasureIndex(from: processedInput)
                                input = ""
                            }
                        }
                        .onSubmit {
                            addMeasureIndex(from: input)
                            input = ""
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(isInputInvalid ? Color.red : Color.clear, lineWidth: 1)
                        )
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func addMeasureIndex(from text: String) {
        guard !text.isEmpty else { return }
        
        if let number = Double(text), (number == floor(number) || number.truncatingRemainder(dividingBy: 1) == 0.5), number > 0 {
            if !indices.contains(number) {
                indices.append(number)
                indices.sort()
            }
            isInputInvalid = false
        } else {
            isInputInvalid = true
        }
    }
    
    private func removeMeasureIndex(_ index: Double) {
        indices.removeAll { $0 == index }
    }
}