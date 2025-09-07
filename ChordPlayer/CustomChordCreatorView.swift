

import SwiftUI

struct CustomChordCreatorView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var customChordManager = CustomChordManager.shared
    
    @State private var chordName: String = ""
    @State private var fingering: [StringOrInt] = Array(repeating: .string("x"), count: 6)
    @State private var showingNameConflictAlert = false
    @State private var showingSaveSuccessAlert = false
    @State private var isPlaying = false
    
    private let maxNameLength = 50
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    nameInputSection
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    FretboardEditor(fingering: $fingering)
                        .padding(.horizontal, 24)
                    
                    if !hasValidFingering() {
                        Text("和弦指法至少需要1个按弦音。")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }
                    
                    previewSection
                        .padding(.horizontal, 24)
                    
                    actionButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("和弦名称冲突", isPresented: $showingNameConflictAlert) {
            Button("取消", role: .cancel) { }
            Button("覆盖") {
                saveChord(overwrite: true)
            }
        } message: {
            Text("和弦名称 \"\(chordName)\" 已存在。是否要覆盖现有的和弦？")
        }
        .alert("保存成功", isPresented: $showingSaveSuccessAlert) {
            Button("确定") {
                dismiss()
            }
        } message: {
            Text("自定义和弦 \"\(chordName)\" 已成功保存！")
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("创建自定义和弦")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("使用指板编辑器创建您的专属和弦")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("取消", role: .cancel) { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(20)
    }
    
    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("和弦名称")
                    .font(.headline)
                Spacer()
                Text("\(chordName.count)/\(maxNameLength)")
                    .font(.caption)
                    .foregroundColor(chordName.count > maxNameLength ? .red : .secondary)
            }
            TextField("例如: C_Custom, Am7_Custom", text: $chordName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: chordName) { _, newValue in
                    if newValue.count > maxNameLength {
                        chordName = String(newValue.prefix(maxNameLength))
                    }
                }
            if chordName.isEmpty {
                Text("请输入和弦名称").font(.caption).foregroundColor(.red)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预览和试听").font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("指法:").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) {
                            stringIndex in
                            let value = fingering[stringIndex]
                            Text(fingeringDisplayText(value))
                                .font(.caption).fontWeight(.medium).foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                        }
                    }
                }
                Spacer()
                Button(action: playChord) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        Text(isPlaying ? "停止" : "试听")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(chordName.isEmpty || !hasValidFingering())
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("清空") { clearAll() }.buttonStyle(.bordered)
            Spacer()
            Button("保存") { saveChord(overwrite: false) }.buttonStyle(.borderedProminent).disabled(!canSave())
        }
    }
    
    private func hasValidFingering() -> Bool {
        let frettedNotesCount = fingering.filter {
            if case .int = $0 { return true } else { return false }
        }.count
        return frettedNotesCount >= 1 // Require at least 1 fretted notes for a valid chord
    }
    
    private func canSave() -> Bool {
        return !chordName.isEmpty && chordName.count <= maxNameLength && hasValidFingering()
    }
    
    private func clearAll() {
        chordName = ""
        fingering = Array(repeating: .string("x"), count: 6)
    }
    
    private func playChord() {
        if isPlaying {
            chordPlayer.panic()
            isPlaying = false
        } else {
            if let patternId = appData.performanceConfig.activePlayingPatternId,
               let pattern = appData.patternLibrary?[appData.performanceConfig.timeSignature]?.first(where: { $0.id == patternId }) {
                playChordWithPattern(chordDefinition: fingering, pattern: pattern)
            } else {
                chordPlayer.playChordDirectly(chordDefinition: fingering, key: appData.performanceConfig.key, capo: 0, velocity: 100, duration: 2.0)
            }
            isPlaying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { isPlaying = false }
        }
    }
    
    private func playChordWithPattern(chordDefinition: [StringOrInt], pattern: GuitarPattern) {
        let tempChordLibrary: ChordLibrary = [chordName: chordDefinition]
        let originalChordLibrary = appData.chordLibrary
        appData.chordLibrary = tempChordLibrary
        
        chordPlayer.playChord(
            chordName: chordName,
            pattern: pattern,
            tempo: appData.performanceConfig.tempo,
            key: appData.performanceConfig.key,
            capo: 0,
            velocity: 100,
            duration: 2.0,
            quantizationMode: .none,
            drumClockInfo: (false, 0, 0)
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appData.chordLibrary = originalChordLibrary
        }
    }
    
    private func saveChord(overwrite: Bool) {
        guard canSave() else { return }
        if customChordManager.chordExists(name: chordName) && !overwrite {
            showingNameConflictAlert = true
            return
        }
        customChordManager.addChord(name: chordName, fingering: fingering)
        showingSaveSuccessAlert = true
    }
    
    private func fingeringDisplayText(_ value: StringOrInt) -> String {
        switch value {
        case .string("x"): return "×"
        case .int(let fret): return "\(fret)"
        case .string(let s): return s
        }
    }
}