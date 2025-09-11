import Foundation
import Combine
import AppKit

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?
    
    @Published var currentMeasure: Int = 0
    @Published var currentBeat: Int = 0
    
    // 跟踪当前active位置是否已经被正确按键触发（用于辅助演奏模式的高亮效果）
    @Published var currentActivePositionTriggered: Bool = false
    
    // 计算正确的初始预备拍状态
    var effectiveCurrentBeat: Int {
        // 如果没有开始演奏（measure=0, beat=0），应该显示预备拍状态
        if currentMeasure == 0 && currentBeat == 0 {
            let timeSigParts = performanceConfig.timeSignature.split(separator: "/")
            let beatsPerMeasure = Int(timeSigParts.first.map(String.init) ?? "4") ?? 4
            return -beatsPerMeasure
        }
        return currentBeat
    }
    @Published var currentlyPlayingChordName: String? = nil
    @Published var currentlyPlayingPatternName: String? = nil
    
    @Published var autoPlaySchedule: [AutoPlayEvent] = []
    
    let customChordManager: CustomChordManager
    
    @Published var playingMode: PlayingMode = .manual {
        didSet {
            buildAutoPlaySchedule()
        }
    }
    
    @Published var performanceConfig: PerformanceConfig {
        didSet {
            presetManager.updateCurrentPreset(performanceConfig: performanceConfig, appConfig: CONFIG)
            buildAutoPlaySchedule()
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

    init(customChordManager: CustomChordManager) {
        self.customChordManager = customChordManager
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
    
    func loadPreset(_ presetInfo: PresetInfo) {
        presetManager.loadPreset(presetInfo)
        // The presetManager's publisher will update the config
    }
    
    func createNewPreset(name: String, description: String? = nil) -> Preset? {
        let shouldInherit = isUnnamedPreset
        let config = shouldInherit ? self.performanceConfig : getDefaultPerformanceConfig()
        let appConfig = shouldInherit ? self.CONFIG : getDefaultAppConfig()
        
        guard let newPreset = presetManager.createNewPreset(name: name, description: description, performanceConfig: config, appConfig: appConfig) else {
            return nil
        }
        // The presetManager's publisher will update the config, so no need to call loadPreset here
        return newPreset
    }
    
    private func getDefaultPerformanceConfig() -> PerformanceConfig {
        return PerformanceConfig(
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
        presetManager.saveCurrentPresetToFile()
        presetManager.savePresetsList()
    }
    
    func resetToDefaults() {
        self.performanceConfig = getDefaultPerformanceConfig()
        self.CONFIG = getDefaultAppConfig()
        self.initializeActivePatterns()
        saveAllData()
        print("[AppData] ✅ Configuration reset to defaults")
    }
    
    // MARK: - Removal Methods
    
    func removeDrumPattern(patternId: String) {
        performanceConfig.selectedDrumPatterns.removeAll { $0 == patternId }
        if performanceConfig.activeDrumPatternId == patternId {
            performanceConfig.activeDrumPatternId = performanceConfig.selectedDrumPatterns.first
        }
    }
    
    func removePlayingPattern(patternId: String) {
        performanceConfig.selectedPlayingPatterns.removeAll { $0 == patternId }
        if performanceConfig.activePlayingPatternId == patternId {
            performanceConfig.activePlayingPatternId = performanceConfig.selectedPlayingPatterns.first
        }
    }
    
    func removeChord(chordName: String) {
        performanceConfig.chords.removeAll { $0.name == chordName }
        buildAutoPlaySchedule()
    }
    
    // MARK: - Auto Play Schedule
    
    private func buildAutoPlaySchedule() {
        guard playingMode == .automatic || playingMode == .assisted else {
            if !autoPlaySchedule.isEmpty {
                autoPlaySchedule = []
            }
            return
        }

        var schedule: [AutoPlayEvent] = []
        let timeSignature = performanceConfig.timeSignature
        var beatsPerMeasure = 4
        let timeSigParts = timeSignature.split(separator: "/")
        if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
            beatsPerMeasure = beats
        }

        for chordConfig in performanceConfig.chords {
            for (shortcut, association) in chordConfig.patternAssociations {
                if let measureIndices = association.measureIndices, !measureIndices.isEmpty {
                    for measureIndex in measureIndices {
                        let targetBeat = (measureIndex - 1) * Double(beatsPerMeasure)
                        let action = AutoPlayEvent(chordName: chordConfig.name, patternId: association.patternId, triggerBeat: Int(round(targetBeat)), shortcut: shortcut.stringValue)
                        schedule.append(action)
                    }
                }
            }
        }
        
        // Sort events by their trigger beat to calculate durations
        var finalSchedule = schedule.sorted { $0.triggerBeat < $1.triggerBeat }

        if !finalSchedule.isEmpty {
            // Find the total length of the performance in beats
            var maxMeasure: Double = 0
            for chordConfig in performanceConfig.chords {
                for (_, association) in chordConfig.patternAssociations {
                    if let measureIndices = association.measureIndices, let maxIndex = measureIndices.max() {
                        maxMeasure = max(maxMeasure, maxIndex)
                    }
                }
            }
            // The total duration is the end of the highest measure number assigned.
            // If the highest is 3.5, it means we have 4 measures total (1, 2, 3, 4).
            let totalMeasures = ceil(maxMeasure)
            let totalBeatsInLoop = Int(totalMeasures * Double(beatsPerMeasure))

            // Calculate duration for each event
            for i in 0..<finalSchedule.count {
                let currentEvent = finalSchedule[i]
                let nextTriggerBeat: Int
                if i < finalSchedule.count - 1 {
                    nextTriggerBeat = finalSchedule[i+1].triggerBeat
                } else {
                    // Last event's duration goes to the end of the loop
                    nextTriggerBeat = totalBeatsInLoop
                }
                finalSchedule[i].durationBeats = nextTriggerBeat - currentEvent.triggerBeat
            }
        }

        autoPlaySchedule = finalSchedule
        let totalDuration = finalSchedule.reduce(0, { $0 + ($1.durationBeats ?? 0) })
        print("[AppData] Auto-play schedule built: \(finalSchedule.count) events, total beats: \(totalDuration)")
    }

    
}