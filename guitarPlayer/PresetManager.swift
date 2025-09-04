import Foundation
import Combine

/// Preset数据模型
struct Preset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String?
    var performanceConfig: PerformanceConfig
    var appConfig: AppConfig
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.performanceConfig = performanceConfig
        self.appConfig = appConfig
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    mutating func update(name: String? = nil, description: String? = nil, performanceConfig: PerformanceConfig? = nil, appConfig: AppConfig? = nil) {
        if let name = name { self.name = name }
        if let description = description { self.description = description }
        if let performanceConfig = performanceConfig { self.performanceConfig = performanceConfig }
        if let appConfig = appConfig { self.appConfig = appConfig }
        self.updatedAt = Date()
    }
}

/// Preset管理器
class PresetManager: ObservableObject {
    static let shared = PresetManager()
    
    @Published var presets: [Preset] = []
    @Published var currentPreset: Preset?
    
    private let presetsURL: URL
    private let currentPresetURL: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        presetsURL = documentsDirectory.appendingPathComponent("presets.json")
        currentPresetURL = documentsDirectory.appendingPathComponent("current_preset.json")
        
        loadPresets()
        loadCurrentPreset()
        
        print("[PresetManager] Initialized with \(presets.count) presets")
    }
    
    // MARK: - 保存和加载
    
    /// 保存所有presets
    private func savePresets() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsURL)
            print("[PresetManager] ✅ Saved \(presets.count) presets")
        } catch {
            print("[PresetManager] ❌ Failed to save presets: \(error)")
        }
    }
    
    /// 加载所有presets
    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path) else {
            print("[PresetManager] No presets file found, starting with empty list")
            return
        }
        
        do {
            let data = try Data(contentsOf: presetsURL)
            presets = try JSONDecoder().decode([Preset].self, from: data)
            print("[PresetManager] ✅ Loaded \(presets.count) presets")
        } catch {
            print("[PresetManager] ❌ Failed to load presets: \(error)")
            presets = []
        }
    }
    
    /// 保存当前preset
    private func saveCurrentPreset() {
        guard let currentPreset = currentPreset else { return }
        
        do {
            let data = try JSONEncoder().encode(currentPreset)
            try data.write(to: currentPresetURL)
            print("[PresetManager] ✅ Saved current preset: \(currentPreset.name)")
        } catch {
            print("[PresetManager] ❌ Failed to save current preset: \(error)")
        }
    }
    
    /// 加载当前preset
    private func loadCurrentPreset() {
        guard FileManager.default.fileExists(atPath: currentPresetURL.path) else {
            print("[PresetManager] No current preset file found")
            return
        }
        
        do {
            let data = try Data(contentsOf: currentPresetURL)
            currentPreset = try JSONDecoder().decode(Preset.self, from: data)
            print("[PresetManager] ✅ Loaded current preset: \(currentPreset?.name ?? "Unknown")")
        } catch {
            print("[PresetManager] ❌ Failed to load current preset: \(error)")
            currentPreset = nil
        }
    }
    
    // MARK: - Preset操作
    
    /// 创建新preset
    func createPreset(name: String, description: String? = nil, from performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Preset? {
        // 检查名称是否已存在
        if presets.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            print("[PresetManager] ❌ Preset with name '\(name)' already exists")
            return nil
        }
        
        let preset = Preset(
            name: name,
            description: description,
            performanceConfig: performanceConfig,
            appConfig: appConfig
        )
        
        presets.append(preset)
        savePresets()
        
        print("[PresetManager] ✅ Created preset: \(name)")
        return preset
    }
    
    /// 更新preset
    func updatePreset(_ preset: Preset, name: String? = nil, description: String? = nil, performanceConfig: PerformanceConfig? = nil, appConfig: AppConfig? = nil) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            print("[PresetManager] ❌ Preset not found for update")
            return false
        }
        
        // 如果更新名称，检查是否与其他preset冲突
        if let newName = name, newName != preset.name {
            if presets.contains(where: { $0.name.lowercased() == newName.lowercased() && $0.id != preset.id }) {
                print("[PresetManager] ❌ Preset with name '\(newName)' already exists")
                return false
            }
        }
        
        presets[index].update(name: name, description: description, performanceConfig: performanceConfig, appConfig: appConfig)
        savePresets()
        
        // 如果更新的是当前preset，也要更新currentPreset
        if currentPreset?.id == preset.id {
            currentPreset = presets[index]
            saveCurrentPreset()
        }
        
        print("[PresetManager] ✅ Updated preset: \(presets[index].name)")
        return true
    }
    
    /// 删除preset
    func deletePreset(_ preset: Preset) -> Bool {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            print("[PresetManager] ❌ Preset not found for deletion")
            return false
        }
        
        let presetName = presets[index].name
        presets.remove(at: index)
        savePresets()
        
        // 如果删除的是当前preset，清除currentPreset
        if currentPreset?.id == preset.id {
            currentPreset = nil
            saveCurrentPreset()
        }
        
        print("[PresetManager] ✅ Deleted preset: \(presetName)")
        return true
    }
    
    /// 加载preset
    func loadPreset(_ preset: Preset) -> (PerformanceConfig, AppConfig) {
        currentPreset = preset
        saveCurrentPreset()
        
        print("[PresetManager] ✅ Loaded preset: \(preset.name)")
        return (preset.performanceConfig, preset.appConfig)
    }
    
    /// 从当前配置创建preset
    func createPresetFromCurrent(name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Preset? {
        return createPreset(name: name, description: description, from: performanceConfig, appConfig: appConfig)
    }
    
    /// 更新当前preset
    func updateCurrentPreset(performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Bool {
        guard let currentPreset = currentPreset else { return false }
        return updatePreset(currentPreset, performanceConfig: performanceConfig, appConfig: appConfig)
    }
    
    // MARK: - 查询方法
    
    /// 根据名称查找preset
    func findPreset(by name: String) -> Preset? {
        return presets.first { $0.name.lowercased() == name.lowercased() }
    }
    
    /// 获取最近使用的presets
    func getRecentPresets(limit: Int = 5) -> [Preset] {
        return Array(presets.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
    
    /// 获取所有preset名称
    func getAllPresetNames() -> [String] {
        return presets.map { $0.name }.sorted()
    }
    
    // MARK: - 调试方法
    
    /// 获取preset统计信息
    func getPresetStats() -> [String: Any] {
        return [
            "total_presets": presets.count,
            "current_preset": currentPreset?.name ?? "None",
            "recent_presets": getRecentPresets(limit: 3).map { $0.name },
            "storage_size": getStorageSize()
        ]
    }
    
    /// 获取存储大小
    private func getStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        if FileManager.default.fileExists(atPath: presetsURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: presetsURL.path)
                totalSize += (attributes[.size] as? Int64) ?? 0
            } catch {}
        }
        
        if FileManager.default.fileExists(atPath: currentPresetURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: currentPresetURL.path)
                totalSize += (attributes[.size] as? Int64) ?? 0
            } catch {}
        }
        
        return totalSize
    }
    
    /// 清除所有presets
    func clearAllPresets() {
        presets.removeAll()
        currentPreset = nil
        savePresets()
        saveCurrentPreset()
        print("[PresetManager] ✅ Cleared all presets")
    }
}
