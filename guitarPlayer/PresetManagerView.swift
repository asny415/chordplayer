import SwiftUI

/// Preset管理主视图
struct PresetManagerView: View {
    @EnvironmentObject var appData: AppData
    @StateObject private var presetManager = PresetManager.shared
    @Environment(\.dismiss) private var dismiss
    
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
            if selectedPreset != nil {
                PresetCreateView()
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preset Manager")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Manage your guitar configurations")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // 当前preset状态卡片
            let currentPreset = presetManager.currentPresetOrUnnamed
            let isUnnamed = presetManager.isUnnamedPreset(currentPreset)
            HStack(spacing: 10) {
                Image(systemName: isUnnamed ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isUnnamed ? .orange : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Preset")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text(currentPreset.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isUnnamed ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isUnnamed ? Color.orange.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
            
            // 关闭按钮
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
            .help("Close")
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    // 悬停效果
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(NSColor.controlBackgroundColor),
                    Color(NSColor.controlBackgroundColor).opacity(0.8)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var searchAndSortBar: some View {
        HStack(spacing: 16) {
            // 搜索框
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 300)
            
            Spacer()
            
            // 排序选择器
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Sort by:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                
                Text("\(filteredAndSortedPresets.count) preset\(filteredAndSortedPresets.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if !searchText.isEmpty {
                    Text("(filtered)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 操作按钮
            HStack(spacing: 12) {
                Button(action: {
                    showingCreateSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Create New")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                Button(action: {
                    // TODO: 实现导入功能
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .medium))
                        Text("Import")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(true)
                
                Button(action: {
                    // TODO: 实现导出功能
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                        Text("Export")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(true)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(NSColor.controlBackgroundColor).opacity(0.8),
                    Color(NSColor.controlBackgroundColor)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.5))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - 方法
    
    private func loadPreset(_ preset: Preset) {
        appData.loadPreset(preset)
        
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
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 16) {
            // 状态指示器和图标
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "folder.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isCurrent ? .green : .blue)
                }
                
                if isCurrent {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .frame(width: 50)
            
            // Preset信息
            VStack(alignment: .leading, spacing: 8) {
                // 标题和日期
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if let description = preset.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Updated")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(formatDate(preset.updatedAt))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 配置标签
                HStack(spacing: 12) {
                    ConfigTag(icon: "metronome", text: "\(Int(preset.performanceConfig.tempo)) BPM", color: .blue)
                    ConfigTag(icon: "music.note", text: preset.performanceConfig.key, color: .purple)
                    ConfigTag(icon: "clock", text: preset.performanceConfig.timeSignature, color: .orange)
                    ConfigTag(icon: "folder", text: "\(preset.performanceConfig.patternGroups.count) groups", color: .green)
                }
            }
            
            Spacer()
            
            // 操作按钮组
            HStack(spacing: 4) {
                ActionButton(icon: "info.circle", color: .secondary, action: onShowDetails, help: "Show Details")
                ActionButton(icon: "arrow.down.circle", color: .blue, action: onLoad, help: "Load Preset")
                ActionButton(icon: "pencil.circle", color: .orange, action: onEdit, help: "Edit Preset")
                ActionButton(icon: "trash.circle", color: .red, action: onDelete, help: "Delete Preset")
            }
            .opacity(isHovered ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isCurrent ? 
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.04)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        gradient: Gradient(colors: [Color(NSColor.controlBackgroundColor), Color(NSColor.controlBackgroundColor).opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isCurrent ? 
                            Color.blue.opacity(0.3) : 
                            Color(NSColor.separatorColor).opacity(0.5), 
                            lineWidth: isCurrent ? 2 : 1
                        )
                )
                .shadow(
                    color: isCurrent ? Color.blue.opacity(0.1) : Color.black.opacity(0.05),
                    radius: isCurrent ? 8 : 4,
                    x: 0,
                    y: isCurrent ? 4 : 2
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
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

// MARK: - 辅助视图

struct ConfigTag: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    let help: String
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isHovered ? .white : color)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isHovered ? color : color.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    PresetManagerView()
        .environmentObject(AppData())
}
