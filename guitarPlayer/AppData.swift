import Foundation
import Combine

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?
    
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
                PatternGroup(name: "Intro", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                // Simplified group name; original intent: Verse/Picking
                PatternGroup(name: "Verse", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC"),
                // Simplified group name; original intent: Chorus/Strum
                PatternGroup(name: "Chorus", patterns: [:], pattern: "ARPEGGIO_4_4_BASIC")
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

        // Load resources
        self.loadData()
        // After loading data, ensure default patterns are valid
        self.initializeDefaultPatterns()
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

}