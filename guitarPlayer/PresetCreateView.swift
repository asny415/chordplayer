import SwiftUI

/// Preset创建视图
struct PresetCreateView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var presetManager: PresetManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var presetName = ""
    @State private var presetDescription = ""
    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 头部信息
                headerSection
                
                // 表单
                formSection
                
                // 预览
                previewSection
                
                Spacer()
                
                // 按钮
                buttonSection
            }
            .padding()
            .frame(minWidth: 500, minHeight: 600)
            .navigationTitle("Create New Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Create a new preset from your current configuration")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 名称输入
            VStack(alignment: .leading, spacing: 8) {
                Label("Preset Name", systemImage: "tag")
                    .font(.headline)
                
                TextField("Enter preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if canCreate {
                            createPreset()
                        }
                    }
                
                if presetName.isEmpty {
                    Text("A name is required")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if presetManager.findPreset(by: presetName) != nil {
                    Text("A preset with this name already exists")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // 描述输入
            VStack(alignment: .leading, spacing: 8) {
                Label("Description (Optional)", systemImage: "text.alignleft")
                    .font(.headline)
                
                TextField("Enter description", text: $presetDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current Configuration Preview", systemImage: "eye")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tempo:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(appData.performanceConfig.tempo)) BPM")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Key:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(appData.performanceConfig.key)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Time Signature:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(appData.performanceConfig.timeSignature)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Pattern Groups:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(appData.performanceConfig.patternGroups.count) groups")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("MIDI Output:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(appData.CONFIG.midiPortName)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var buttonSection: some View {
        HStack {
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Create Preset") {
                createPreset()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreate || isCreating)
            .overlay {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
    }
    
    private var canCreate: Bool {
        !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        presetManager.findPreset(by: presetName) == nil
    }
    
    private func createPreset() {
        guard canCreate else { return }
        
        isCreating = true
        
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = presetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        if let _ = appData.createNewPreset(
            name: trimmedName,
            description: finalDescription
        ) {
            dismiss()
        } else {
            errorMessage = "Failed to create preset. Please try again."
            showingError = true
        }
        
        isCreating = false
    }
}

/// Preset编辑视图
struct PresetEditView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var presetManager: PresetManager
    @Environment(\.dismiss) private var dismiss
    
    let preset: Preset
    
    @State private var presetName: String
    @State private var presetDescription: String
    @State private var isUpdating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingUpdateConfigAlert = false
    
    init(preset: Preset) {
        self.preset = preset
        self._presetName = State(initialValue: preset.name)
        self._presetDescription = State(initialValue: preset.description ?? "")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 头部信息
                headerSection
                
                // 表单
                formSection
                
                // 配置信息
                configSection
                
                Spacer()
                
                // 按钮
                buttonSection
            }
            .padding()
            .frame(minWidth: 500, minHeight: 600)
            .navigationTitle("Edit Preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Update Configuration", isPresented: $showingUpdateConfigAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Update") {
                updatePresetWithCurrentConfig()
            }
        } message: {
            Text("Do you want to update this preset with your current configuration? This will overwrite the existing configuration.")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Edit preset information and configuration")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 名称输入
            VStack(alignment: .leading, spacing: 8) {
                Label("Preset Name", systemImage: "tag")
                    .font(.headline)
                
                TextField("Enter preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                
                if presetName.isEmpty {
                    Text("A name is required")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if presetName != preset.name && presetManager.findPreset(by: presetName) != nil {
                    Text("A preset with this name already exists")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // 描述输入
            VStack(alignment: .leading, spacing: 8) {
                Label("Description (Optional)", systemImage: "text.alignleft")
                    .font(.headline)
                
                TextField("Enter description", text: $presetDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Preset Configuration", systemImage: "gear")
                    .font(.headline)
                
                Spacer()
                
                Button("Update with Current") {
                    showingUpdateConfigAlert = true
                }
                .buttonStyle(.bordered)
                .help("Update this preset with your current configuration")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tempo:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(preset.performanceConfig.tempo)) BPM")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Key:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(preset.performanceConfig.key)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Time Signature:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(preset.performanceConfig.timeSignature)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Pattern Groups:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(preset.performanceConfig.patternGroups.count) groups")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Created:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatDate(preset.createdAt))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Last Modified:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatDate(preset.updatedAt))
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var buttonSection: some View {
        HStack {
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            
            Button("Save Changes") {
                updatePreset()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canUpdate || isUpdating)
            .overlay {
                if isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
    }
    
    private var canUpdate: Bool {
        !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (presetName != preset.name ? presetManager.findPreset(by: presetName) == nil : true)
    }
    
    private func updatePreset() {
        guard canUpdate else { return }
        
        isUpdating = true
        
        let trimmedName = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = presetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
        
        // 更新Preset名称和描述
        var updatedPreset = preset
        updatedPreset.name = trimmedName
        updatedPreset.description = finalDescription
        updatedPreset.updatedAt = Date()
        
        // 保存更新后的Preset
        if let index = presetManager.presets.firstIndex(where: { $0.id == preset.id }) {
            presetManager.presets[index] = updatedPreset
            presetManager.savePresetsToFile()
            dismiss()
        } else {
            errorMessage = "Failed to update preset. Please try again."
            showingError = true
        }
        
        isUpdating = false
    }
    
    private func updatePresetWithCurrentConfig() {
        // 更新Preset的配置
        var updatedPreset = preset
        updatedPreset.performanceConfig = appData.performanceConfig
        updatedPreset.appConfig = appData.CONFIG
        updatedPreset.updatedAt = Date()
        
        // 保存更新后的Preset
        if let index = presetManager.presets.firstIndex(where: { $0.id == preset.id }) {
            presetManager.presets[index] = updatedPreset
            presetManager.savePresetsToFile()
            // 配置已更新，可以关闭对话框
        } else {
            errorMessage = "Failed to update preset configuration. Please try again."
            showingError = true
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
    PresetCreateView()
        .environmentObject(AppData())
        .environmentObject(PresetManager.shared)
}
