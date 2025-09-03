import Foundation
import Combine

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?
    
    // Runtime-only per-group settings (session-level, not persisted)
    @Published var runtimeGroupSettings: [Int: GroupRuntimeSettings]

    // Configuration properties
    @Published var performanceConfig: PerformanceConfig
    let KEY_CYCLE: [String]
    let TIME_SIGNATURE_CYCLE: [String]
    
    let CONFIG: AppConfig
    

    init() {
        // Initialize configuration properties with default values from JS files
            self.performanceConfig = PerformanceConfig(
            tempo: 120,
            timeSignature: "4/4",
            key: "C",
            quantize: QuantizationMode.measure.rawValue, // Use rawValue for enum
            quantizeToggleKey: "q",
            drumPattern: "ROCK_4_4_BASIC",
            
            keyMap: [:],
            patternGroups: [
                // Simplified group names for clarity; original intent: Intro/Arpeggio
                PatternGroup(name: "Intro", patterns: ["__default__": nil]),
                // Simplified group name; original intent: Verse/Picking
                PatternGroup(name: "Verse", patterns: ["__default__": nil]),
                // Simplified group name; original intent: Chorus/Strum
                PatternGroup(name: "Chorus", patterns: ["__default__": nil])
            ]
        )

        self.KEY_CYCLE = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ]
        self.TIME_SIGNATURE_CYCLE = ["4/4", "3/4", "6/8"]
        
        self.CONFIG = AppConfig(
            midiPortName: "IAC驱动程序 总线1",
            note: 60,
            velocity: 64,
            duration: 4000,
            channel: 0
        )

        self.runtimeGroupSettings = [:]

        // Load resources
        self.loadData()
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

}

// Runtime-only settings for a group (not persisted)
struct GroupRuntimeSettings {
    var fingeringId: String?
    
}