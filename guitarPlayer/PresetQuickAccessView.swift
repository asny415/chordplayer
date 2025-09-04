import SwiftUI

/// Preset快速访问组件
struct PresetQuickAccessView: View {
    @EnvironmentObject var appData: AppData
    @StateObject private var presetManager = PresetManager.shared
    
    @State private var showingPresetManager = false
    @State private var showingCreateSheet = false
    @State private var selectedPreset: Preset?
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            headerView
            
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    // 当前preset显示
                    currentPresetView
                    
                    // 快速访问列表
                    quickAccessList
                    
                    // 操作按钮
                    actionButtons
                }
                .padding()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .sheet(isPresented: $showingPresetManager) {
            PresetManagerView()
                .environmentObject(appData)
                .environmentObject(presetManager)
        }
        .sheet(isPresented: $showingCreateSheet) {
            PresetCreateView()
                .environmentObject(appData)
                .environmentObject(presetManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LoadPreset"))) { notification in
            if let userInfo = notification.userInfo,
               let performanceConfig = userInfo["performanceConfig"] as? PerformanceConfig,
               let appConfig = userInfo["appConfig"] as? AppConfig {
                appData.performanceConfig = performanceConfig
                appData.CONFIG = appConfig
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 12) {
                    // Preset Icon with Status
                    let currentPreset = presetManager.currentPresetOrUnnamed
                    let isUnnamed = presetManager.isUnnamedPreset(currentPreset)
                    
                    ZStack {
                        Circle()
                            .fill(isUnnamed ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: isUnnamed ? "folder" : "folder.fill")
                            .font(.system(size: 16))
                            .foregroundColor(isUnnamed ? .orange : .blue)
                    }
                    
                    // Preset Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Presets")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            Text(currentPreset.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            // Status Badge
                            Text(isUnnamed ? "Unsaved" : "Active")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isUnnamed ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                                )
                                .foregroundColor(isUnnamed ? .orange : .green)
                        }
                    }
                    
                    // Quick Stats
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(currentPreset.performanceConfig.tempo)) BPM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(currentPreset.performanceConfig.key) • \(currentPreset.performanceConfig.timeSignature)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Expand/Collapse Arrow
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(isExpanded ? 0 : 0))
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
            
            // Quick Action Buttons
            HStack(spacing: 8) {
                Button(action: { showingCreateSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Create New Preset")
                
                Button(action: { showingPresetManager = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Manage Presets")
            }
        }
        .padding()
    }
    
    private var currentPresetView: some View {
        let currentPreset = presetManager.currentPresetOrUnnamed
        let isUnnamed = presetManager.isUnnamedPreset(currentPreset)
        
        return HStack {
            Image(systemName: isUnnamed ? "circle" : "checkmark.circle.fill")
                .foregroundColor(isUnnamed ? .secondary : .green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(currentPreset.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let description = currentPreset.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if !isUnnamed {
                Text("Active")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var quickAccessList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Presets")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            if presetManager.presets.isEmpty {
                Text("No presets available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(presetManager.getRecentPresets(limit: 3)) { preset in
                    PresetQuickAccessRow(
                        preset: preset,
                        isCurrent: presetManager.currentPreset?.id == preset.id,
                        onLoad: { loadPreset(preset) }
                    )
                }
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Create New") {
                showingCreateSheet = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("Manage All") {
                showingPresetManager = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
        }
    }
    
    private func loadPreset(_ preset: Preset) {
        appData.loadPreset(preset)
    }
}

/// Preset快速访问行
struct PresetQuickAccessRow: View {
    let preset: Preset
    let isCurrent: Bool
    let onLoad: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Preset Icon
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isCurrent ? .green : .blue)
            }
            
            // Preset Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if isCurrent {
                        Text("Current")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                            )
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "metronome")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Int(preset.performanceConfig.tempo)) BPM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(preset.performanceConfig.key)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(preset.performanceConfig.timeSignature)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let description = preset.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Load Button
            Button(action: onLoad) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                    Text("Load")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.7)
            .help("Load Preset")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.green.opacity(0.1) : (isHovered ? Color.blue.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? Color.green.opacity(0.3) : (isHovered ? Color.blue.opacity(0.2) : Color.clear), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

/// Preset状态指示器（用于控制栏）
struct PresetStatusIndicator: View {
    @StateObject private var presetManager = PresetManager.shared
    
    var body: some View {
        HStack(spacing: 6) {
            let currentPreset = presetManager.currentPresetOrUnnamed
            let isUnnamed = presetManager.isUnnamedPreset(currentPreset)
            
            Image(systemName: isUnnamed ? "folder" : "folder.fill")
                .foregroundColor(isUnnamed ? .secondary : .blue)
            
            Text(currentPreset.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if !isUnnamed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

#Preview {
    VStack {
        PresetQuickAccessView()
            .environmentObject(AppData())
        
        Divider()
        
        PresetStatusIndicator()
    }
    .padding()
}
