import Foundation
import Combine
import AppKit

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?
    
    @Published var customChordManager = CustomChordManager.shared
    
    @Published var performanceConfig: PerformanceConfig {
        didSet {
            presetManager.updateCurrentPreset(performanceConfig: performanceConfig, appConfig: CONFIG)
        }
    }
    
    @Published var CONFIG: AppConfig {
        didSet {
            presetManager.updateCurrentPreset(performanceConfig: performanceConfig, appConfig: CONFIG)
        }
    }
    
    let KEY_CYCLE: [String]
    let TIME_SIGNATURE_CYCLE: [String]
    
    private let presetManager = PresetManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.KEY_CYCLE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        self.TIME_SIGNATURE_CYCLE = ["4/4", "3/4", "6/8"]
        
        let currentPreset = presetManager.currentPresetOrUnnamed
        self.performanceConfig = currentPreset.performanceConfig
        self.CONFIG = currentPreset.appConfig
        
        print("[AppData] ✅ Loaded config from preset: \(currentPreset.name)")

        self.loadData()
        self.initializeActivePatterns()
        self.setupAppLifecycleHandling()
        
        presetManager.$currentPreset
            .compactMap { $0 }
            .sink { [weak self] newPreset in
                guard let self = self else { return }
                if self.performanceConfig != newPreset.performanceConfig || self.CONFIG != newPreset.appConfig {
                    self.performanceConfig = newPreset.performanceConfig
                    self.CONFIG = newPreset.appConfig
                    self.initializeActivePatterns()
                    print("[AppData] ✅ Updated config from PresetManager.currentPreset: \(newPreset.name)")
                }
            }
            .store(in: &cancellables)
        
        customChordManager.$customChords
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateCombinedChordLibrary()
            }
            .store(in: &cancellables)
    }

    private func loadData() {
        let builtInChordLibrary = DataLoader.load(filename: "chords", as: ChordLibrary.self)
        drumPatternLibrary = DataLoader.load(filename: "drums", as: DrumPatternLibrary.self)
        patternLibrary = DataLoader.load(filename: "patterns", as: PatternLibrary.self)

        if let builtInChords = builtInChordLibrary {
            chordLibrary = customChordManager.combinedChordLibrary(with: builtInChords)
        } else {
            chordLibrary = customChordManager.customChords
        }
    }
    
    private func updateCombinedChordLibrary() {
        if let builtInChords = DataLoader.load(filename: "chords", as: ChordLibrary.self) {
            chordLibrary = customChordManager.combinedChordLibrary(with: builtInChords)
        }
    }

    private func initializeActivePatterns() {
        if performanceConfig.activePlayingPatternId == nil,
           let firstPatternId = performanceConfig.selectedPlayingPatterns.first {
            performanceConfig.activePlayingPatternId = firstPatternId
        }
        
        if performanceConfig.activeDrumPatternId == nil,
           let firstDrumId = performanceConfig.selectedDrumPatterns.first {
            performanceConfig.activeDrumPatternId = firstDrumId
        }
    }
    
    private func setupAppLifecycleHandling() {
        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.saveAllData() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.saveAllData() }
            .store(in: &cancellables)
    }
    
    func loadPreset(_ preset: Preset) {
        let (newPerformanceConfig, newAppConfig) = presetManager.loadPreset(preset)
        self.performanceConfig = newPerformanceConfig
        self.CONFIG = newAppConfig
        self.initializeActivePatterns()
        print("[AppData] ✅ Loaded preset: \(preset.name)")
    }
    
    func createNewPreset(name: String, description: String? = nil) -> Preset? {
        let shouldInherit = isUnnamedPreset
        let config = shouldInherit ? self.performanceConfig : getDefaultPerformanceConfig()
        let appConfig = shouldInherit ? self.CONFIG : getDefaultAppConfig()
        
        guard let newPreset = presetManager.createNewPreset(name: name, description: description, performanceConfig: config, appConfig: appConfig) else {
            return nil
        }
        loadPreset(newPreset)
        return newPreset
    }
    
    private func getDefaultPerformanceConfig() -> PerformanceConfig {
        return PerformanceConfig(
            tempo: 120,
            timeSignature: "4/4",
            key: "C",
            quantize: QuantizationMode.measure.rawValue,
            chords: [],
            selectedDrumPatterns: ["ROCK_4_4_BASIC"],
            selectedPlayingPatterns: ["4-4-1-1"],
            activeDrumPatternId: "ROCK_4_4_BASIC",
            activePlayingPatternId: "4-4-1-1"
        )
    }
    
    private func getDefaultAppConfig() -> AppConfig {
        return AppConfig(midiPortName: "IAC Driver Bus 1", note: 60, velocity: 64, duration: 4000, channel: 0)
    }
    
    var currentPreset: Preset {
        return presetManager.currentPresetOrUnnamed
    }
    
    var isUnnamedPreset: Bool {
        return presetManager.isUnnamedPreset(currentPreset)
    }
    
    func saveAllData() {
        print("[AppData] Saving data...")
        presetManager.savePresetsToFile()
    }
    
    func resetToDefaults() {
        self.performanceConfig = getDefaultPerformanceConfig()
        self.CONFIG = getDefaultAppConfig()
        self.initializeActivePatterns()
        saveAllData()
        print("[AppData] ✅ Configuration reset to defaults")
    }
}