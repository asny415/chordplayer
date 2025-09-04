import Foundation
import Combine
import AppKit

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?
    
    // Configuration properties - 现在通过PresetManager管理
    @Published var performanceConfig: PerformanceConfig {
        didSet {
            // 自动保存到当前活跃的Preset
            presetManager.scheduleAutoSave(performanceConfig: performanceConfig, appConfig: CONFIG)
        }
    }
    
    @Published var CONFIG: AppConfig {
        didSet {
            // 自动保存到当前活跃的Preset
            presetManager.scheduleAutoSave(performanceConfig: performanceConfig, appConfig: CONFIG)
        }
    }
    
    let KEY_CYCLE: [String]
    let TIME_SIGNATURE_CYCLE: [String]
    
    // Preset管理器
    private let presetManager = PresetManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // 先设置常量
        self.KEY_CYCLE = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ]
        self.TIME_SIGNATURE_CYCLE = ["4/4", "3/4", "6/8"]
        
        // 从当前活跃的Preset加载配置
        let currentPreset = presetManager.currentPresetOrUnnamed
        self.performanceConfig = currentPreset.performanceConfig
        self.CONFIG = currentPreset.appConfig
        
        print("[AppData] ✅ Loaded config from preset: \(currentPreset.name)")

        // Load resources
        self.loadData()
        // After loading data, ensure default patterns are valid
        self.initializeDefaultPatterns()
        
        // 设置应用生命周期监听
        self.setupAppLifecycleHandling()
    }

    // Load data files into libraries
    private func loadData() {
        chordLibrary = DataLoader.load(filename: "chords", as: ChordLibrary.self)
        drumPatternLibrary = DataLoader.load(filename: "drums", as: DrumPatternLibrary.self)
        patternLibrary = DataLoader.load(filename: "patterns", as: PatternLibrary.self)

        if chordLibrary == nil { print("Failed to load chordLibrary") }
        if drumPatternLibrary == nil { print("Failed to load drumPatternLibrary") }
        if patternLibrary == nil { print("Failed to load patternLibrary") }
        print("Loaded patternLibrary: \(String(describing: patternLibrary))")
        if let pl = patternLibrary { print("PatternLibrary keys: \(pl.keys.sorted().joined(separator: ", "))") }
    }

    // Ensures that each group's default pattern is a valid ID from the loaded patternLibrary.
    private func initializeDefaultPatterns() {
        guard let patternLibrary = self.patternLibrary else { return }

        for i in 0..<performanceConfig.patternGroups.count {
            var group = performanceConfig.patternGroups[i]
            let timeSig = performanceConfig.timeSignature // Use current global time signature for fallback

            // If the current pattern is invalid or nil, try to find a valid one.
            if group.pattern == nil || !isValidPatternId(group.pattern!, forTimeSignature: timeSig, in: patternLibrary) {
                // Try to find a default pattern for the current time signature
                if let defaultPattern = patternLibrary[timeSig]?.first {
                    group.pattern = defaultPattern.id
                } else {
                    // Fallback to "4/4" if no patterns for current time signature
                    if let fallbackPattern = patternLibrary["4/4"]?.first {
                        group.pattern = fallbackPattern.id
                    } else {
                        // If even "4/4" has no patterns, set to nil (should not happen if patterns.json is valid)
                        group.pattern = nil
                        print("Warning: No valid default pattern found for group '\(group.name)' and time signature '\(timeSig)' or '4/4'.")
                    }
                }
            }
            performanceConfig.patternGroups[i] = group
        }
    }

    // Helper to check if a pattern ID is valid for a given time signature
    private func isValidPatternId(_ id: String, forTimeSignature timeSig: String, in library: PatternLibrary) -> Bool {
        return library[timeSig]?.contains(where: { $0.id == id }) ?? false
    }
    
    // MARK: - 应用生命周期处理
    
    /// 设置应用生命周期监听
    private func setupAppLifecycleHandling() {
        // 监听应用进入后台
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)
        
        // 监听应用即将终止
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.handleAppWillTerminate()
            }
            .store(in: &cancellables)
        
        // 监听系统即将关闭
        NotificationCenter.default.publisher(for: NSWorkspace.willPowerOffNotification)
            .sink { [weak self] _ in
                self?.handleSystemWillPowerOff()
            }
            .store(in: &cancellables)
    }
    
    /// 应用即将失去焦点时保存数据
    private func handleAppWillResignActive() {
        print("[AppData] App will resign active - saving data...")
        presetManager.saveImmediately(performanceConfig: performanceConfig, appConfig: CONFIG)
    }
    
    /// 应用即将终止时保存数据
    private func handleAppWillTerminate() {
        print("[AppData] App will terminate - saving data...")
        presetManager.saveImmediately(performanceConfig: performanceConfig, appConfig: CONFIG)
    }
    
    /// 系统即将关闭时保存数据
    private func handleSystemWillPowerOff() {
        print("[AppData] System will power off - saving data...")
        presetManager.saveImmediately(performanceConfig: performanceConfig, appConfig: CONFIG)
    }
    
    // MARK: - Preset相关方法
    
    /// 加载指定的Preset
    func loadPreset(_ preset: Preset) {
        let (newPerformanceConfig, newAppConfig) = presetManager.loadPreset(preset)
        
        // 更新当前配置
        self.performanceConfig = newPerformanceConfig
        self.CONFIG = newAppConfig
        
        // 重新初始化默认模式
        self.initializeDefaultPatterns()
        
        print("[AppData] ✅ Loaded preset: \(preset.name)")
    }
    
    /// 创建新的Preset
    func createNewPreset(name: String, description: String? = nil) -> Preset? {
        return presetManager.createNewPreset(
            name: name,
            description: description,
            performanceConfig: performanceConfig,
            appConfig: CONFIG
        )
    }
    
    /// 获取当前活跃的Preset
    var currentPreset: Preset {
        return presetManager.currentPresetOrUnnamed
    }
    
    /// 检查当前是否为"未命名"Preset
    var isUnnamedPreset: Bool {
        return presetManager.isUnnamedPreset(currentPreset)
    }
    
    // MARK: - 公共方法
    
    /// 手动保存所有数据
    func saveAllData() {
        print("[AppData] Manual save requested")
        presetManager.saveImmediately(performanceConfig: performanceConfig, appConfig: CONFIG)
    }
    
    /// 重置所有配置到默认值
    func resetToDefaults() {
        print("[AppData] Resetting to default configuration")
        
        // 重置到默认值
        self.performanceConfig = PerformanceConfig(
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
        )
        
        self.CONFIG = AppConfig(
            midiPortName: "IAC驱动程序 总线1",
            note: 60,
            velocity: 64,
            duration: 4000,
            channel: 0
        )
        
        // 重新初始化默认模式
        self.initializeDefaultPatterns()
        
        // 立即保存到当前Preset
        presetManager.saveImmediately(performanceConfig: performanceConfig, appConfig: CONFIG)
        
        print("[AppData] ✅ Configuration reset to defaults")
    }
    
    /// 获取Preset统计信息（用于调试）
    func getPresetInfo() -> [String: Any] {
        return presetManager.getPresetStats()
    }
}