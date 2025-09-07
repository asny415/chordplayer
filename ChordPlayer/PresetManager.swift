import Foundation
import Combine

class PresetManager: ObservableObject {
    static let shared = PresetManager()
    
    @Published var presets: [PresetInfo] = []
    @Published var currentPreset: Preset?
    
    private let unnamedPresetId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private let presetsDirectory: URL
    private var presetsListURL: URL {
        return presetsDirectory.appendingPathComponent("presets.json")
    }
    
    private var autoSaveTimer: Timer?
    private let autoSaveDelay: TimeInterval = 1.0
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let baseDirectory = documentsPath.appendingPathComponent("ChordPlayer")
        presetsDirectory = baseDirectory.appendingPathComponent("Presets")
        
        try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        
        migrateIfNeeded(in: baseDirectory)
        
        loadPresetsList()
        
        if presets.isEmpty {
            let defaultPreset = createDefaultPreset()
            presets.append(defaultPreset.toInfo())
            savePresetToFile(defaultPreset)
            savePresetsList()
        }
        
        if let firstPresetInfo = presets.first {
            loadPreset(firstPresetInfo)
        }
        
        print("[PresetManager] Initialized with \(presets.count) presets. Current: \(currentPreset?.name ?? "None")")
    }
    
    var currentPresetOrUnnamed: Preset {
        return currentPreset ?? createDefaultPreset(isUnnamed: true)
    }
    
    func isUnnamedPreset(_ preset: Preset) -> Bool {
        return preset.id == unnamedPresetId
    }
    
    func loadPreset(_ presetInfo: PresetInfo) {
        let fileURL = presetFileURL(for: presetInfo.id)
        do {
            let data = try Data(contentsOf: fileURL)
            let preset = try JSONDecoder().decode(Preset.self, from: data)
            self.currentPreset = preset
            print("[PresetManager] ✅ Loaded preset: \(preset.name)")
        } catch {
            print("[PresetManager] ❌ Failed to load preset file for \(presetInfo.name): \(error)")
        }
    }
    
    func createNewPreset(name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) -> Preset? {
        if presets.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            print("[PresetManager] ❌ Preset with name '\(name)' already exists")
            return nil
        }
        
        let newPreset = Preset(name: name, description: description, performanceConfig: performanceConfig, appConfig: appConfig)
        presets.append(newPreset.toInfo())
        currentPreset = newPreset
        
        savePresetsList()
        saveCurrentPresetToFile()
        
        print("[PresetManager] ✅ Created preset: \(name)")
        return newPreset
    }
    
    func updateCurrentPreset(performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        guard var preset = currentPreset else { return }
        
        preset.performanceConfig = performanceConfig
        preset.appConfig = appConfig
        preset.updatedAt = Date()
        
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index].updatedAt = preset.updatedAt
        }
        
        currentPreset = preset
        scheduleAutoSave()
    }
    
    func deletePreset(_ presetInfo: PresetInfo) {
        guard presetInfo.id != unnamedPresetId else { return }
        
        presets.removeAll { $0.id == presetInfo.id }
        
        let fileURL = presetFileURL(for: presetInfo.id)
        try? FileManager.default.removeItem(at: fileURL)
        
        if presets.isEmpty {
            let defaultPreset = createDefaultPreset()
            presets.append(defaultPreset.toInfo())
            savePresetToFile(defaultPreset)
        }
        
        if currentPreset?.id == presetInfo.id {
            if let firstPreset = presets.first {
                loadPreset(firstPreset)
            } else {
                currentPreset = nil
            }
        }
        
        savePresetsList()
    }
    
    func renamePreset(_ presetInfo: PresetInfo, newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == presetInfo.id }) else { return }
        if presets.contains(where: { $0.id != presetInfo.id && $0.name.lowercased() == newName.lowercased() }) { return }
        
        presets[index].name = newName
        presets[index].updatedAt = Date()
        
        if var presetToRename = currentPreset, presetToRename.id == presetInfo.id {
            presetToRename.name = newName
            presetToRename.updatedAt = Date()
            currentPreset = presetToRename
            saveCurrentPresetToFile()
        } else if let presetToRename = loadFullPreset(for: presetInfo.id) {
            var mutablePreset = presetToRename
            mutablePreset.name = newName
            mutablePreset.updatedAt = Date()
            savePresetToFile(mutablePreset)
        }
        
        savePresetsList()
    }
    
    func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            self?.saveCurrentPresetToFile()
            self?.savePresetsList()
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
        
        let preset = Preset(
            id: isUnnamed ? unnamedPresetId : UUID(),
            name: isUnnamed ? String(localized: "preset_manager_unnamed_preset_name") : "Default Preset",
            description: isUnnamed ? String(localized: "preset_manager_unnamed_preset_description") : nil,
            performanceConfig: defaultConfig,
            appConfig: defaultAppConfig
        )
        return preset
    }
    
    func setShortcut(_ shortcut: Shortcut?, forChord chord: String) {
        guard var preset = currentPreset else { return }
        
        if let s = shortcut {
            preset.chordShortcuts[chord] = s
        } else {
            preset.chordShortcuts.removeValue(forKey: chord)
        }
        preset.updatedAt = Date()
        currentPreset = preset
        
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index].updatedAt = preset.updatedAt
        }
        
        scheduleAutoSave()
    }
    
    // MARK: - File storage helpers
    
    private func presetFileURL(for id: UUID) -> URL {
        return presetsDirectory.appendingPathComponent("preset_\(id.uuidString).json")
    }
    
    private func loadPresetsList() {
        guard FileManager.default.fileExists(atPath: presetsListURL.path) else {
            self.presets = []
            return
        }
        do {
            let data = try Data(contentsOf: presetsListURL)
            let infos = try JSONDecoder().decode([PresetInfo].self, from: data)
            self.presets = infos.sorted(by: { $0.updatedAt > $1.updatedAt })
        } catch {
            print("[PresetManager] ❌ Failed to load presets list: \(error).")
            self.presets = []
        }
    }
    
    func savePresetsList() {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsListURL, options: .atomic)
        } catch {
            print("[PresetManager] ❌ Failed to save presets list: \(error)")
        }
    }
    
    func saveCurrentPresetToFile() {
        guard let preset = currentPreset else { return }
        savePresetToFile(preset)
    }
    
    private func savePresetToFile(_ preset: Preset) {
        let url = presetFileURL(for: preset.id)
        do {
            let data = try JSONEncoder().encode(preset)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[PresetManager] ❌ Failed to save preset \(preset.name): \(error)")
        }
    }
    
    private func loadFullPreset(for id: UUID) -> Preset? {
        let fileURL = presetFileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Preset.self, from: data)
        } catch {
            print("[PresetManager] ⚠️ Could not load full preset for id \(id): \(error)")
            return nil
        }
    }
    
    private func migrateIfNeeded(in baseDirectory: URL) {
        // Migration from single file v2
        let combinedV2 = baseDirectory.appendingPathComponent("presets_v2.json")
        if FileManager.default.fileExists(atPath: combinedV2.path) {
            do {
                let data = try Data(contentsOf: combinedV2)
                let combinedPresets = try JSONDecoder().decode([Preset].self, from: data)
                var infos: [PresetInfo] = []
                for preset in combinedPresets {
                    savePresetToFile(preset)
                    infos.append(preset.toInfo())
                }
                self.presets = infos
                savePresetsList()
                try FileManager.default.removeItem(at: combinedV2)
                print("[PresetManager] 🔁 Migrated \(combinedPresets.count) presets from presets_v2.json.")
                return // Exit after this migration
            } catch {
                print("[PresetManager] ⚠️ Migration from v2 failed: \(error)")
            }
        }
        
        // Migration from individual files to presets.json + individual files
        if !FileManager.default.fileExists(atPath: presetsListURL.path) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                var loadedPresets: [Preset] = []
                for file in files where file.pathExtension.lowercased() == "json" {
                    if let preset = loadFullPreset(for: UUID(uuidString: file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "preset_", with: "")) ?? UUID()) {
                        loadedPresets.append(preset)
                    }
                }
                
                if !loadedPresets.isEmpty {
                    self.presets = loadedPresets.map { $0.toInfo() }
                    savePresetsList()
                    print("[PresetManager] 🔁 Migrated \(loadedPresets.count) individual preset files to new list format.")
                }
            } catch {
                print("[PresetManager] ⚠️ Migration from individual files failed: \(error)")
            }
        }
    }
}


