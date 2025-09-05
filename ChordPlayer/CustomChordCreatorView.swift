import SwiftUI

/// 自定义和弦创建器
struct CustomChordCreatorView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
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
            // 标题栏
            headerView
            
            Divider()
            
            // 主要内容
            ScrollView {
                VStack(spacing: 20) {
                    // 和弦名称输入
                    nameInputSection
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    // 指板编辑器
                    FretboardEditor(fingering: $fingering)
                        .padding(.horizontal, 24)
                    
                    // 预览和试听
                    previewSection
                        .padding(.horizontal, 24)
                    
                    // 操作按钮
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
    
    // MARK: - 子视图
    
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
            
            Button("取消", role: .cancel) {
                dismiss()
            }
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
                    // 限制长度
                    if newValue.count > maxNameLength {
                        chordName = String(newValue.prefix(maxNameLength))
                    }
                }
            
            if chordName.isEmpty {
                Text("请输入和弦名称")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预览和试听")
                .font(.headline)
            
            HStack(spacing: 16) {
                // 指法显示
                VStack(alignment: .leading, spacing: 8) {
                    Text("指法:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { stringIndex in
                            let value = fingering[stringIndex]
                            Text(fingeringDisplayText(value))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        }
                    }
                }
                
                Spacer()
                
                // 试听按钮
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("清空") {
                clearAll()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("保存") {
                saveChord(overwrite: false)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave())
        }
    }
    
    // MARK: - 辅助方法
    
    private func hasValidFingering() -> Bool {
        return fingering.contains { value in
            switch value {
            case .int(_):
                return true
            case .string("x"):
                return false
            case .string(_):
                return false
            }
        }
    }
    
    private func canSave() -> Bool {
        return !chordName.isEmpty && 
               chordName.count <= maxNameLength && 
               hasValidFingering()
    }
    
    private func clearAll() {
        chordName = ""
        fingering = Array(repeating: .string("x"), count: 6)
    }
    
    private func playChord() {
        if isPlaying {
            // 停止播放
            chordPlayer.panic()
            isPlaying = false
        } else {
            // 开始播放
            // 获取当前活动组的默认指法
            if let activeGroupId = keyboardHandler.activeGroupId,
               let activeGroup = appData.performanceConfig.patternGroups.first(where: { $0.id == activeGroupId }),
               let patternId = activeGroup.pattern,
               let pattern = appData.patternLibrary?[appData.performanceConfig.timeSignature]?.first(where: { $0.id == patternId }) {
                
                // 使用组的默认指法播放和弦
                playChordWithPattern(
                    chordDefinition: fingering,
                    pattern: pattern,
                    tempo: appData.performanceConfig.tempo,
                    key: appData.performanceConfig.key,
                    capo: 0,
                    velocity: 100,
                    duration: 2.0
                )
            } else {
                // 如果没有找到组的默认指法，使用简单播放
                chordPlayer.playChordDirectly(
                    chordDefinition: fingering,
                    key: appData.performanceConfig.key,
                    capo: 0,
                    velocity: 100,
                    duration: 2.0
                )
            }
            
            isPlaying = true
            
            // 2秒后自动停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isPlaying = false
            }
        }
    }
    
    private func playChordWithPattern(chordDefinition: [StringOrInt], pattern: GuitarPattern, tempo: Double, key: String, capo: Int, velocity: UInt8, duration: TimeInterval) {
        // 创建临时和弦库
        let tempChordLibrary: ChordLibrary = [chordName: chordDefinition]
        
        // 临时替换和弦库
        let originalChordLibrary = appData.chordLibrary
        appData.chordLibrary = tempChordLibrary
        
        // 播放和弦
        chordPlayer.playChord(
            chordName: chordName,
            pattern: pattern,
            tempo: tempo,
            key: key,
            capo: capo,
            velocity: velocity,
            duration: duration
        )
        
        // 恢复原始和弦库
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
        case .string("x"):
            return "×"
        case .int(let fret):
            return "\(fret)"
        case .string(let s):
            return s
        }
    }
}

// MARK: - 预览
struct CustomChordCreatorView_Previews: PreviewProvider {
    static var previews: some View {
        CustomChordCreatorView()
            .environmentObject(AppData())
    }
}
