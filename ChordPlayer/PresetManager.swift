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
    private let presetsDirectory: URL
    
    private var autoSaveTimer: Timer?
    private let autoSaveDelay: TimeInterval = 1.0
    
    private init() {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let baseDirectory = documentsPath.appendingPathComponent("ChordPlayer")
    presetsDirectory = baseDirectory.appendingPathComponent("Presets")

    try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)

    // If there's an old combined file, migrate it to per-preset files.
    migrateCombinedFileIfNeeded(in: baseDirectory)

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
    
    // MARK: - File storage helpers

    private func presetFileURL(for id: UUID) -> URL {
        return presetsDirectory.appendingPathComponent("preset_\(id.uuidString).json")
    }

    private func loadPresets() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            var loaded: [Preset] = []
            for file in files where file.pathExtension.lowercased() == "json" {
                do {
                    let data = try Data(contentsOf: file)
                    let p = try JSONDecoder().decode(Preset.self, from: data)
                    loaded.append(p)
                } catch {
                    print("[PresetManager] ⚠️ Failed to load preset file \(file.lastPathComponent): \(error)")
                }
            }
            // Keep the on-disk order; if none, empty array.
            self.presets = loaded
        } catch {
            print("[PresetManager] ❌ Failed to read presets directory: \(error). Creating default.")
            self.presets = []
        }
    }

    func savePresetsToFile() {
        // Save each preset into its own file. Remove orphaned files that don't correspond to current presets.
        do {
            var expectedFiles = Set<String>()
            for preset in presets {
                let url = presetFileURL(for: preset.id)
                let data = try JSONEncoder().encode(preset)
                try data.write(to: url, options: .atomic)
                expectedFiles.insert(url.lastPathComponent)
            }

            // Clean up any other JSON files in the presets directory that are not part of current presets
            let existing = try FileManager.default.contentsOfDirectory(at: presetsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in existing where file.pathExtension.lowercased() == "json" {
                if !expectedFiles.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            }

            print("[PresetManager] ✅ Presets saved to individual files. Count: \(presets.count)")
        } catch {
            print("[PresetManager] ❌ Failed to save presets: \(error)")
        }
    }

    // If the old single-file format exists, migrate it into per-preset files and remove the old file.
    private func migrateCombinedFileIfNeeded(in baseDirectory: URL) {
        let combined = baseDirectory.appendingPathComponent("presets_v2.json")
        guard FileManager.default.fileExists(atPath: combined.path) else { return }

        do {
            let data = try Data(contentsOf: combined)
            let combinedPresets = try JSONDecoder().decode([Preset].self, from: data)
            if !combinedPresets.isEmpty {
                for preset in combinedPresets {
                    let url = presetFileURL(for: preset.id)
                    let pData = try JSONEncoder().encode(preset)
                    try pData.write(to: url, options: .atomic)
                }
                // remove old combined file
                try FileManager.default.removeItem(at: combined)
                print("[PresetManager] 🔁 Migrated \(combinedPresets.count) presets from presets_v2.json to individual files.")
            }
        } catch {
            print("[PresetManager] ⚠️ Migration failed: \(error)")
        }
    }
}