import Foundation
import Combine

struct Preset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String?
    // map chordID (e.g. "A_Major") -> Shortcut (user assigned)
    var chordShortcuts: [String: Shortcut]
    var performanceConfig: PerformanceConfig
    var appConfig: AppConfig
    var createdAt: Date
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        self.id = id
        self.name = name
        self.description = description
    self.chordShortcuts = [:]
        self.performanceConfig = performanceConfig
        self.appConfig = appConfig
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

class PresetManager: ObservableObject {
    static let shared = PresetManager()
    
    @Published var presets: [Preset] = []
    @Published var currentPreset: Preset?
    
    private let unnamedPresetId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private let presetsFile: URL
    
    private var autoSaveTimer: Timer?
    private let autoSaveDelay: TimeInterval = 1.0
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let presetsDirectory = documentsPath.appendingPathComponent("ChordPlayer")
        presetsFile = presetsDirectory.appendingPathComponent("presets_v2.json")
        
        try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        
        loadPresets()
        
        if presets.isEmpty {
            let defaultPreset = createDefaultPreset()
            presets.append(defaultPreset)
            savePresetsToFile()
        }
        
        currentPreset = presets.first
        print("[PresetManager] Initialized with \(presets.count) presets. Current: \(currentPreset?.name ?? "None")")
    }
    
    var currentPresetOrUnnamed: Preset {
        return currentPreset ?? createDefaultPreset(isUnnamed: true)
    }
    
    func isUnnamedPreset(_ preset: Preset) -> Bool {
        return preset.id == unnamedPresetId
    }
    
    func loadPreset(_ preset: Preset) -> (PerformanceConfig, AppConfig) {
        currentPreset = preset
        print("[PresetManager] ✅ Loaded preset: \(preset.name)")
        return (preset.performanceConfig, preset.appConfig)
    }
    
    func createNewPreset(name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Preset? {
        if presets.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            print("[PresetManager] ❌ Preset with name '\(name)' already exists")
            return nil
        }
        
        let newPreset = Preset(name: name, description: description, performanceConfig: performanceConfig, appConfig: appConfig)
        presets.append(newPreset)
        currentPreset = newPreset
        savePresetsToFile()
        print("[PresetManager] ✅ Created preset: \(name)")
        return newPreset
    }
    
    func updateCurrentPreset(performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        guard let currentId = currentPreset?.id, let index = presets.firstIndex(where: { $0.id == currentId }) else {
            return
        }
        
        presets[index].performanceConfig = performanceConfig
        presets[index].appConfig = appConfig
        presets[index].updatedAt = Date()
        scheduleAutoSave()
    }
    
    func deletePreset(_ preset: Preset) {
        guard !isUnnamedPreset(preset), let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        
        presets.remove(at: index)
        if presets.isEmpty {
            presets.append(createDefaultPreset())
        }
        
        if currentPreset?.id == preset.id {
            currentPreset = presets.first
        }
        savePresetsToFile()
    }
    
    func renamePreset(_ preset: Preset, newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        if presets.contains(where: { $0.id != preset.id && $0.name.lowercased() == newName.lowercased() }) { return }
        
        presets[index].name = newName
        presets[index].updatedAt = Date()
        if currentPreset?.id == preset.id {
            currentPreset = presets[index]
        }
        savePresetsToFile()
    }
    
    func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            self?.savePresetsToFile()
        }
    }
    
    private func createDefaultPreset(isUnnamed: Bool = false) -> Preset {
        let defaultConfig = PerformanceConfig(
            tempo: 120,
            timeSignature: "4/4",
            key: "C",
            quantize: QuantizationMode.measure.rawValue,
            chords: [],
            selectedDrumPatterns: [],
            selectedPlayingPatterns: [],
            activeDrumPatternId: "",
            activePlayingPatternId: ""
        )
        let defaultAppConfig = AppConfig(midiPortName: "IAC Driver Bus 1", note: 60, velocity: 64, duration: 4000, channel: 0)
        
        var preset = Preset(
            id: isUnnamed ? unnamedPresetId : UUID(),
            name: isUnnamed ? String(localized: "preset_manager_unnamed_preset_name") : "Default Preset",
            description: isUnnamed ? String(localized: "preset_manager_unnamed_preset_description") : nil,
            performanceConfig: defaultConfig,
            appConfig: defaultAppConfig
        )
        preset.chordShortcuts = [:]
        return preset
    }

    // Assign or remove a shortcut for a chord in the currently loaded preset
    func setShortcut(_ shortcut: Shortcut?, forChord chord: String) {
        guard let current = currentPreset, let index = presets.firstIndex(where: { $0.id == current.id }) else { return }

        if let s = shortcut {
            presets[index].chordShortcuts[chord] = s
        } else {
            presets[index].chordShortcuts.removeValue(forKey: chord)
        }

        presets[index].updatedAt = Date()
        // reflect change to currentPreset reference
        currentPreset = presets[index]
        scheduleAutoSave()
    }
    
    private func loadPresets() {
        do {
            let data = try Data(contentsOf: presetsFile)
            self.presets = try JSONDecoder().decode([Preset].self, from: data)
        } catch {
            print("[PresetManager] ❌ Failed to load presets: \(error). Creating default.")
            self.presets = []
        }
    }
    
    func savePresetsToFile() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsFile, options: .atomic)
            print("[PresetManager] ✅ Presets saved to file.")
        } catch {
            print("[PresetManager] ❌ Failed to save presets: \(error)")
        }
    }
}