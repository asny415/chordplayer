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

/// 统一的Preset管理器 - 所有配置都通过Preset管理
class PresetManager: ObservableObject {
    static let shared = PresetManager()
    
    @Published var presets: [Preset] = []
    @Published var currentPreset: Preset?
    
    // 特殊的"未命名"Preset ID
    private let unnamedPresetId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    private let presetsDirectory: URL
    private let presetsFile: URL
    private let unnamedPresetFile: URL
    
    // 自动保存定时器
    private var autoSaveTimer: Timer?
    private let autoSaveDelay: TimeInterval = 2.0
    
    private init() {
        // 设置存储路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        presetsDirectory = documentsPath.appendingPathComponent("GuitarPlayer")
        presetsFile = presetsDirectory.appendingPathComponent("presets.json")
        unnamedPresetFile = presetsDirectory.appendingPathComponent("unnamed_preset.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        
        // 加载现有presets
        loadPresets()
        
        // 确保始终有一个活跃的Preset
        ensureActivePreset()
        
        print("[PresetManager] Initialized with \(presets.count) presets, current: \(currentPreset?.name ?? "未命名")")
    }
    
    // MARK: - 核心方法
    
    /// 获取当前活跃的Preset（如果不存在则创建"未命名"）
    var currentPresetOrUnnamed: Preset {
        if let current = currentPreset {
            return current
        } else {
            return createUnnamedPreset()
        }
    }
    
    /// 检查是否为"未命名"Preset
    func isUnnamedPreset(_ preset: Preset) -> Bool {
        return preset.id == unnamedPresetId
    }
    
    /// 获取所有Preset（包括"未命名"）
    var allPresets: [Preset] {
        var all = presets
        // 如果当前没有活跃Preset，添加"未命名"
        if currentPreset == nil {
            all.insert(createUnnamedPreset(), at: 0)
        }
        return all
    }
    
    // MARK: - Preset Operations
    
    /// 加载Preset并设置为当前活跃
    func loadPreset(_ preset: Preset) -> (PerformanceConfig, AppConfig) {
        currentPreset = preset
        saveCurrentPreset()
        
        print("[PresetManager] ✅ Loaded preset: \(preset.name)")
        return (preset.performanceConfig, preset.appConfig)
    }
    
    /// 创建新的命名Preset
    func createNewPreset(name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Preset? {
        // 检查名称是否已存在
        if presets.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            print("[PresetManager] ❌ Preset with name '\(name)' already exists")
            return nil
        }
        
        let newPreset = Preset(
            name: name,
            description: description,
            performanceConfig: performanceConfig,
            appConfig: appConfig
        )
        
        presets.append(newPreset)
        currentPreset = newPreset
        
        // 保存到文件
        savePresetsToFile()
        saveCurrentPreset()
        
        print("[PresetManager] ✅ Created preset: \(name)")
        return newPreset
    }
    
    /// 更新当前活跃Preset的配置
    func updateCurrentPreset(performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        let targetPreset = currentPresetOrUnnamed
        
        // 更新配置
        var updatedPreset = targetPreset
        updatedPreset.performanceConfig = performanceConfig
        updatedPreset.appConfig = appConfig
        updatedPreset.updatedAt = Date()
        
        // 如果是"未命名"Preset，更新当前Preset
        if isUnnamedPreset(targetPreset) {
            currentPreset = updatedPreset
            saveUnnamedPreset(updatedPreset)
        } else {
            // 更新Preset列表中的对应项
            if let index = presets.firstIndex(where: { $0.id == targetPreset.id }) {
                presets[index] = updatedPreset
                currentPreset = updatedPreset
                savePresetsToFile()
            }
        }
        
        // 保存当前Preset状态
        saveCurrentPreset()
    }
    
    /// 删除Preset
    func deletePreset(_ preset: Preset) -> Bool {
        // 不能删除"未命名"Preset
        if isUnnamedPreset(preset) {
            print("[PresetManager] ❌ Cannot delete unnamed preset")
            return false
        }
        
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            print("[PresetManager] ❌ Preset not found for deletion")
            return false
        }
        
        let presetName = presets[index].name
        presets.remove(at: index)
        savePresetsToFile()
        
        // 如果删除的是当前preset，切换到"未命名"
        if currentPreset?.id == preset.id {
            currentPreset = nil
            saveCurrentPreset()
        }
        
        print("[PresetManager] ✅ Deleted preset: \(presetName)")
        return true
    }
    
    // MARK: - 自动保存
    
    /// 调度自动保存
    func scheduleAutoSave(performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { _ in
            self.updateCurrentPreset(performanceConfig: performanceConfig, appConfig: appConfig)
        }
    }
    
    /// 立即保存
    func saveImmediately(performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        autoSaveTimer?.invalidate()
        updateCurrentPreset(performanceConfig: performanceConfig, appConfig: appConfig)
    }
    
    // MARK: - 私有方法
    
    /// 创建"未命名"Preset
    private func createUnnamedPreset() -> Preset {
        // 尝试从文件加载"未命名"Preset
        if let savedUnnamed = loadUnnamedPreset() {
            return savedUnnamed
        }
        
        // 创建新的"未命名"Preset
        return Preset(
            name: "未命名",
            description: "自动保存的配置",
            performanceConfig: PerformanceConfig(
                tempo: 120,
                timeSignature: "4/4",
                key: "C",
                quantize: QuantizationMode.measure.rawValue,
                quantizeToggleKey: "q",
                drumPattern: "ROCK_4_4_BASIC",
                keyMap: [:],
                patternGroups: [
                    PatternGroup(name: "Intro", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                    PatternGroup(name: "Verse", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                    PatternGroup(name: "Chorus", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC")
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
    }
    
    /// 确保始终有一个活跃的Preset
    private func ensureActivePreset() {
        if currentPreset == nil {
            currentPreset = createUnnamedPreset()
            saveCurrentPreset()
        }
    }
    
    /// 保存"未命名"Preset到文件
    private func saveUnnamedPreset(_ preset: Preset) {
        do {
            let data = try JSONEncoder().encode(preset)
            try data.write(to: unnamedPresetFile)
        } catch {
            print("[PresetManager] ❌ Failed to save unnamed preset: \(error)")
        }
    }
    
    /// 从文件加载"未命名"Preset
    private func loadUnnamedPreset() -> Preset? {
        do {
            let data = try Data(contentsOf: unnamedPresetFile)
            return try JSONDecoder().decode(Preset.self, from: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - 文件操作
    
    private func loadPresets() {
        do {
            let data = try Data(contentsOf: presetsFile)
            presets = try JSONDecoder().decode([Preset].self, from: data)
            print("[PresetManager] ✅ Loaded \(presets.count) presets")
        } catch {
            print("[PresetManager] ❌ Failed to load presets: \(error)")
            presets = []
        }
    }
    
    func savePresetsToFile() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsFile)
        } catch {
            print("[PresetManager] ❌ Failed to save presets: \(error)")
        }
    }
    
    private func saveCurrentPreset() {
        guard let currentPreset = currentPreset else { return }
        
        do {
            let data = try JSONEncoder().encode(currentPreset)
            let currentPresetFile = presetsDirectory.appendingPathComponent("current_preset.json")
            try data.write(to: currentPresetFile)
        } catch {
            print("[PresetManager] ❌ Failed to save current preset: \(error)")
        }
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
            "current_preset": currentPreset?.name ?? "未命名",
            "is_unnamed": isUnnamedPreset(currentPresetOrUnnamed),
            "recent_presets": getRecentPresets(limit: 3).map { $0.name },
            "storage_size": getStorageSize(),
            "presets_file": presetsFile.path,
            "unnamed_file": unnamedPresetFile.path
        ]
    }
    
    /// 获取存储大小
    private func getStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        if FileManager.default.fileExists(atPath: presetsFile.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: presetsFile.path)
                totalSize += (attributes[.size] as? Int64) ?? 0
            } catch {}
        }
        
        if FileManager.default.fileExists(atPath: unnamedPresetFile.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: unnamedPresetFile.path)
                totalSize += (attributes[.size] as? Int64) ?? 0
            } catch {}
        }
        
        return totalSize
    }
    
    /// 清除所有presets
    func clearAllPresets() {
        presets.removeAll()
        currentPreset = nil
        savePresetsToFile()
        saveCurrentPreset()
        print("[PresetManager] ✅ Cleared all presets")
    }
}