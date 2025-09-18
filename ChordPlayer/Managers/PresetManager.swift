import Foundation
import Combine

class PresetManager: ObservableObject {
    static let shared = PresetManager()
    
    @Published var presets: [PresetInfo] = []
    @Published var currentPreset: Preset?
    
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
        
        loadPresetsList()
        
        if presets.isEmpty {
            let defaultPreset = Preset.createNew(name: "Default Preset")
            presets.append(defaultPreset.toInfo())
            savePresetToFile(defaultPreset)
            savePresetsList()
        }
        
        if let firstPresetInfo = presets.first {
            loadPreset(firstPresetInfo)
        } else {
            print("[PresetManager] CRITICAL: Failed to load or create an initial preset.")
        }
    }
    
    func loadPreset(_ presetInfo: PresetInfo) {
        let fileURL = presetFileURL(for: presetInfo.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: fileURL)
            let preset = try decoder.decode(Preset.self, from: data)
            self.currentPreset = preset
        } catch {
            print("[PresetManager] ❌ Failed to load or decode preset file for \(presetInfo.name): \(error). This might be an old format.")
            // Handle failure: e.g., remove from list and load another
            presets.removeAll { $0.id == presetInfo.id }
            savePresetsList()
            if let nextPreset = presets.first {
                loadPreset(nextPreset)
            } else {
                currentPreset = nil // Or create a new default one
            }
        }
    }
    
    func createNewPreset(name: String) -> Preset {
        let newName = getUniquePresetName(name)
        let newPreset = Preset.createNew(name: newName)
        
        presets.insert(newPreset.toInfo(), at: 0)
        currentPreset = newPreset
        
        savePresetsList()
        saveCurrentPresetToFile()
        
        return newPreset
    }
    
    func updateCurrentPreset(_ preset: Preset) {
        guard let presetId = currentPreset?.id, preset.id == presetId else { return }
        
        var updatedPreset = preset
        updatedPreset.updatedAt = Date()
        self.currentPreset = updatedPreset
        
        if let index = presets.firstIndex(where: { $0.id == presetId }) {
            presets[index].name = updatedPreset.name
            presets[index].updatedAt = updatedPreset.updatedAt
        }
        
        scheduleAutoSave()
    }
    
    func deletePreset(_ presetInfo: PresetInfo) {
        presets.removeAll { $0.id == presetInfo.id }
        
        let fileURL = presetFileURL(for: presetInfo.id)
        try? FileManager.default.removeItem(at: fileURL)
        
        if presets.isEmpty {
            let defaultPreset = Preset.createNew(name: "Default Preset")
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
        
        let finalName = getUniquePresetName(newName, ignoring: presetInfo.id)
        presets[index].name = finalName
        presets[index].updatedAt = Date()
        
        if var presetToRename = currentPreset, presetToRename.id == presetInfo.id {
            presetToRename.name = finalName
            presetToRename.updatedAt = Date()
            currentPreset = presetToRename
            saveCurrentPresetToFile()
        } else {
            // Load the preset, rename it, and save it back
            if var presetToRename = loadFullPreset(for: presetInfo.id) {
                presetToRename.name = finalName
                presetToRename.updatedAt = Date()
                savePresetToFile(presetToRename)
            }
        }
        
        savePresetsList()
    }
    
    func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
            self?.saveCurrentPresetToFile()
        }
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: presetsListURL)
            let infos = try decoder.decode([PresetInfo].self, from: data)
            self.presets = infos.sorted(by: { $0.updatedAt > $1.updatedAt })
        } catch {
            print("[PresetManager] ❌ Failed to load presets list: \(error).")
            self.presets = []
        }
    }
    
    func savePresetsList() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(presets)
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            let data = try encoder.encode(preset)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[PresetManager] ❌ Failed to save preset \(preset.name): \(error)")
        }
    }
    
    private func loadFullPreset(for id: UUID) -> Preset? {
        let fileURL = presetFileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(Preset.self, from: data)
        } catch {
            print("[PresetManager] ⚠️ Could not load full preset for id \(id): \(error)")
            return nil
        }
    }
    
    private func getUniquePresetName(_ name: String, ignoring idToIgnore: UUID? = nil) -> String {
        var newName = name
        var counter = 1
        while presets.contains(where: { $0.name.lowercased() == newName.lowercased() && $0.id != idToIgnore }) {
            counter += 1
            newName = "\(name) \(counter)"
        }
        return newName
    }
}