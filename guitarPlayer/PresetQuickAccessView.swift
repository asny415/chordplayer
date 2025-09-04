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
        VStack(alignment: .leading, spacing: 8) {
            // 头部
            headerView
            
            if isExpanded {
                // 当前preset显示
                currentPresetView
                
                // 快速访问列表
                quickAccessList
                
                // 操作按钮
                actionButtons
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    
                    Text("Presets")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    let currentPreset = presetManager.currentPresetOrUnnamed
                    Text("• \(currentPreset.name)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // 快速操作按钮
            HStack(spacing: 8) {
                Button(action: { showingCreateSheet = true }) {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Create New Preset")
                
                Button(action: { showingPresetManager = true }) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Manage Presets")
            }
        }
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
        HStack(spacing: 8) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "folder")
                .foregroundColor(isCurrent ? .green : .blue)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(Int(preset.performanceConfig.tempo)) BPM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(preset.performanceConfig.key)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(preset.performanceConfig.timeSignature)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: onLoad) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.6)
            .help("Load Preset")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.green.opacity(0.1) : Color.clear)
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
