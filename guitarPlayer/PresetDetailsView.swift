import SwiftUI

/// Preset详情视图
struct PresetDetailsView: View {
    @EnvironmentObject var presetManager: PresetManager
    @Environment(\.dismiss) private var dismiss
    
    let preset: Preset
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 头部信息
                    headerSection
                    
                    // 基本信息
                    basicInfoSection
                    
                    // 性能配置详情
                    performanceConfigSection
                    
                    // 应用配置详情
                    appConfigSection
                    
                    // 模式组详情
                    patternGroupsSection
                }
                .padding()
            }
            .frame(minWidth: 600, minHeight: 700)
            .navigationTitle("Preset Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Load Preset") {
                        loadPreset()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let description = preset.description, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 状态指示器
                if presetManager.currentPreset?.id == preset.id {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Current")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            // 时间信息
            HStack(spacing: 20) {
                Label(formatDate(preset.createdAt), systemImage: "calendar.badge.plus")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label(formatDate(preset.updatedAt), systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Basic Information", systemImage: "info.circle")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Preset ID", value: preset.id.uuidString)
                InfoRow(label: "Name", value: preset.name)
                InfoRow(label: "Description", value: preset.description ?? "No description")
                InfoRow(label: "Created", value: formatDate(preset.createdAt))
                InfoRow(label: "Last Modified", value: formatDate(preset.updatedAt))
            }
        }
    }
    
    private var performanceConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Performance Configuration", systemImage: "music.note")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Tempo", value: "\(Int(preset.performanceConfig.tempo)) BPM")
                InfoRow(label: "Key", value: preset.performanceConfig.key)
                InfoRow(label: "Time Signature", value: preset.performanceConfig.timeSignature)
                InfoRow(label: "Quantization", value: preset.performanceConfig.quantize ?? "None")
                InfoRow(label: "Quantize Toggle Key", value: preset.performanceConfig.quantizeToggleKey ?? "None")
                InfoRow(label: "Drum Pattern", value: preset.performanceConfig.drumPattern ?? "None")
                InfoRow(label: "Pattern Groups", value: "\(preset.performanceConfig.patternGroups.count) groups")
                InfoRow(label: "Key Mappings", value: "\(preset.performanceConfig.keyMap.count) mappings")
            }
        }
    }
    
    private var appConfigSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Application Configuration", systemImage: "gear")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "MIDI Port", value: preset.appConfig.midiPortName)
                InfoRow(label: "Note", value: "\(preset.appConfig.note)")
                InfoRow(label: "Velocity", value: "\(preset.appConfig.velocity)")
                InfoRow(label: "Duration", value: "\(preset.appConfig.duration) ms")
                InfoRow(label: "Channel", value: "\(preset.appConfig.channel)")
            }
        }
    }
    
    private var patternGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pattern Groups", systemImage: "folder")
                .font(.headline)
            
            if preset.performanceConfig.patternGroups.isEmpty {
                Text("No pattern groups configured")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(preset.performanceConfig.patternGroups.enumerated()), id: \.offset) { index, group in
                    PatternGroupCard(group: group, index: index)
                }
            }
        }
    }
    
    private func loadPreset() {
        let (performanceConfig, appConfig) = presetManager.loadPreset(preset)
        
        // 这里需要通知AppData更新配置
        // 由于我们无法直接访问AppData，我们通过通知中心发送消息
        NotificationCenter.default.post(
            name: NSNotification.Name("LoadPreset"),
            object: nil,
            userInfo: [
                "performanceConfig": performanceConfig,
                "appConfig": appConfig
            ]
        )
        
        dismiss()
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 信息行组件
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// 模式组卡片
struct PatternGroupCard: View {
    let group: PatternGroup
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Group \(index + 1): \(group.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let pattern = group.pattern {
                    Text(pattern)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            if !group.chordAssignments.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chord Assignments:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 4) {
                        ForEach(Array(group.chordAssignments.keys.sorted()), id: \.self) { chordName in
                            HStack(spacing: 4) {
                                Text(chordName)
                                    .font(.caption2)
                                
                                if let assignment = group.chordAssignments[chordName],
                                   let shortcut = assignment.shortcutKey {
                                    Text(shortcut)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    let samplePreset = Preset(
        name: "Rock Ballad",
        description: "Perfect for emotional rock ballads",
        performanceConfig: PerformanceConfig(
            tempo: 80,
            timeSignature: "4/4",
            key: "C",
            quantize: "measure",
            quantizeToggleKey: "q",
            drumPattern: "ROCK_4_4_BASIC",
            keyMap: [:],
            patternGroups: [
                PatternGroup(name: "Intro", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                PatternGroup(name: "Verse", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                PatternGroup(name: "Chorus", patterns: [:], pattern: "STRUM_4_4_BASIC")
            ]
        ),
        appConfig: AppConfig(
            midiPortName: "IAC驱动程序 总线1",
            note: 60,
            velocity: 64,
            duration: 4000,
            channel: 0
        )
    )
    
    PresetDetailsView(preset: samplePreset)
        .environmentObject(PresetManager.shared)
}
