import SwiftUI

/// Preset管理主视图
struct PresetManagerView: View {
    @EnvironmentObject var appData: AppData
    @StateObject private var presetManager = PresetManager.shared
    
    @State private var showingCreateSheet = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var selectedPreset: Preset?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .name
    @State private var showingPresetDetails = false
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case dateCreated = "Date Created"
        case dateModified = "Date Modified"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
    var filteredAndSortedPresets: [Preset] {
        var filtered = presetManager.presets
        
        // 搜索过滤
        if !searchText.isEmpty {
            filtered = filtered.filter { preset in
                preset.name.localizedCaseInsensitiveContains(searchText) ||
                (preset.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // 排序
        switch sortOption {
        case .name:
            filtered.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .dateModified:
            filtered.sort { $0.updatedAt > $1.updatedAt }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            headerView
            
            Divider()
            
            // 搜索和排序栏
            searchAndSortBar
            
            Divider()
            
            // 主要内容区域
            if filteredAndSortedPresets.isEmpty {
                emptyStateView
            } else {
                presetListView
            }
            
            Divider()
            
            // 底部操作栏
            bottomActionBar
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(isPresented: $showingCreateSheet) {
            PresetCreateView()
                .environmentObject(appData)
                .environmentObject(presetManager)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let selectedPreset = selectedPreset {
                PresetEditView(preset: selectedPreset)
                    .environmentObject(appData)
                    .environmentObject(presetManager)
            }
        }
        .sheet(isPresented: $showingPresetDetails) {
            if let selectedPreset = selectedPreset {
                PresetDetailsView(preset: selectedPreset)
                    .environmentObject(presetManager)
            }
        }
        .alert("Delete Preset", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let preset = selectedPreset {
                    _ = presetManager.deletePreset(preset)
                }
            }
        } message: {
            if let preset = selectedPreset {
                Text("Are you sure you want to delete '\(preset.name)'? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - 子视图
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preset Manager")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Manage your guitar configurations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 当前preset指示器
            if let currentPreset = presetManager.currentPreset {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Current: \(currentPreset.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private var searchAndSortBar: some View {
        HStack(spacing: 12) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            
            Spacer()
            
            // 排序选择器
            HStack(spacing: 8) {
                Text("Sort by:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Presets Found")
                .font(.title3)
                .fontWeight(.medium)
            
            if searchText.isEmpty {
                Text("Create your first preset to save your current configuration")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Create Preset") {
                    showingCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No presets match your search criteria")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Clear Search") {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var presetListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredAndSortedPresets) { preset in
                    PresetRowView(
                        preset: preset,
                        isCurrent: presetManager.currentPreset?.id == preset.id,
                        onLoad: { loadPreset(preset) },
                        onEdit: { 
                            selectedPreset = preset
                            showingEditSheet = true
                        },
                        onDelete: {
                            selectedPreset = preset
                            showingDeleteAlert = true
                        },
                        onShowDetails: {
                            selectedPreset = preset
                            showingPresetDetails = true
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    private var bottomActionBar: some View {
        HStack {
            // 统计信息
            Text("\(filteredAndSortedPresets.count) preset\(filteredAndSortedPresets.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 12) {
                Button("Create New") {
                    showingCreateSheet = true
                }
                .buttonStyle(.bordered)
                
                Button("Import") {
                    // TODO: 实现导入功能
                }
                .buttonStyle(.bordered)
                .disabled(true)
                
                Button("Export") {
                    // TODO: 实现导出功能
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 方法
    
    private func loadPreset(_ preset: Preset) {
        let (performanceConfig, appConfig) = presetManager.loadPreset(preset)
        
        // 更新AppData
        appData.performanceConfig = performanceConfig
        appData.CONFIG = appConfig
        
        print("[PresetManagerView] Loaded preset: \(preset.name)")
    }
}

/// Preset行视图
struct PresetRowView: View {
    let preset: Preset
    let isCurrent: Bool
    let onLoad: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onShowDetails: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标和状态
            VStack {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "folder.fill")
                    .font(.title2)
                    .foregroundColor(isCurrent ? .green : .blue)
                
                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
            .frame(width: 40)
            
            // Preset信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(formatDate(preset.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let description = preset.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // 配置摘要
                HStack(spacing: 16) {
                    Label("\(Int(preset.performanceConfig.tempo)) BPM", systemImage: "metronome")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(preset.performanceConfig.key, systemImage: "music.note")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(preset.performanceConfig.timeSignature, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(preset.performanceConfig.patternGroups.count) groups", systemImage: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 8) {
                Button(action: onShowDetails) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Show Details")
                
                Button(action: onLoad) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Load Preset")
                
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Edit Preset")
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Preset")
            }
            .opacity(isHovered ? 1.0 : 0.6)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isCurrent ? Color.blue.opacity(0.3) : Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    PresetManagerView()
        .environmentObject(AppData())
}
