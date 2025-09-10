import Foundation

// For chords.json
enum StringOrInt: Codable, Hashable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        throw DecodingError.typeMismatch(StringOrInt.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a String or Int"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x):
            try container.encode(x)
        case .int(let x):
            try container.encode(x)
        }
    }
}

typealias ChordLibrary = [String: [StringOrInt]]

// For drums.json
struct DrumPatternEvent: Codable, Hashable {
    var delay: String
    let notes: [Int]
}

struct DrumPattern: Codable, Hashable {
    let displayName: String
    let pattern: [DrumPatternEvent]

    enum CodingKeys: String, CodingKey {
        case displayName
        case pattern
    }
    
    // MARK: - Grid Conversion Logic

    /// Converts a DrumPattern's event array into a 2D grid and determines the subdivision.
    static func toGrid(pattern: DrumPattern, timeSignature: String, instruments: [Int]) -> (grid: [[Bool]], subdivision: Int) {
        // First, determine the most likely subdivision by inspecting the delays
        var is16th = false
        for event in pattern.pattern {
            if event.delay.contains("16") {
                is16th = true
                break
            }
            if let den = event.delay.split(separator: "/").last.flatMap({ Double($0) }), den > 8 {
                is16th = true
                break
            }
        }
        let subdivision = is16th ? 16 : 8
        
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let stepsPerBeat = subdivision / (timeSignature == "6/8" ? 2 : 4) // For 6/8, a beat is a dotted quarter
        let totalSteps = beats * stepsPerBeat
        
        var grid = Array(repeating: Array(repeating: false, count: totalSteps), count: instruments.count)
        
        var cumulativeTime: Double = 0.0 // Time as a fraction of a whole note

        for event in pattern.pattern {
            if let delayFraction = MusicTheory.parseDelay(delayString: event.delay) {
                cumulativeTime += delayFraction
            }
            
            // Convert fraction of whole note to step index
            let step = Int(round(cumulativeTime * Double(subdivision))) // Assuming 4/4, whole note = 16 steps for 16th subdivision

            if step < totalSteps {
                for note in event.notes {
                    if let instrumentIndex = instruments.firstIndex(of: note) {
                        grid[instrumentIndex][step] = true
                    }
                }
            }
        }
        
        return (grid, subdivision)
    }

    /// Converts a 2D grid state into an array of DrumPatternEvents.
    static func fromGrid(grid: [[Bool]], subdivision: Int, instruments: [Int]) -> [DrumPatternEvent] {
        var patternEvents: [DrumPatternEvent] = []
        guard !grid.isEmpty, !grid[0].isEmpty else { return [] }

        let totalSteps = grid[0].count
        var lastEventStep = 0

        for col in 0..<totalSteps {
            let notesForThisStep: [Int] = instruments.indices.compactMap { row in
                grid[row][col] ? instruments[row] : nil
            }

            if !notesForThisStep.isEmpty {
                let stepDifference = col - lastEventStep
                let delayString = "\(stepDifference)/\(subdivision)"
                
                // For the very first event, if it's at step 0, the format should be 0/X, not 0.0
                // The logic naturally handles this now. If col is 0, stepDifference is 0.
                patternEvents.append(DrumPatternEvent(delay: delayString, notes: notesForThisStep))
                lastEventStep = col
            }
        }
        return patternEvents
    }
}

typealias DrumPatternLibrary = [String: [String: DrumPattern]]

// For patterns.json

// Represents a note in a guitar playing pattern.
// It can be a simple integer (physical string), a string (relative to root),
// or a complex object specifying a precise fret on a string.
enum GuitarNote: Codable, Hashable {
    case chordString(Int)
    case chordRoot(String)
    case specificFret(string: Int, fret: Int)

    private enum CodingKeys: String, CodingKey {
        case type, string, fret
    }

    init(from decoder: Decoder) throws {
        // First, try to decode as a simple value (Int or String)
        if let singleValueContainer = try? decoder.singleValueContainer() {
            if let intValue = try? singleValueContainer.decode(Int.self) {
                self = .chordString(intValue)
                return
            }
            if let stringValue = try? singleValueContainer.decode(String.self) {
                self = .chordRoot(stringValue)
                return
            }
        }

        // If not a simple value, try to decode as a complex object
        do {
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            if let type = try keyedContainer.decodeIfPresent(String.self, forKey: .type), type == "specificFret" {
                let string = try keyedContainer.decode(Int.self, forKey: .string)
                let fret = try keyedContainer.decode(Int.self, forKey: .fret)
                self = .specificFret(string: string, fret: fret)
                return
            }
        } catch {
            // Fallthrough to the error below if decoding as a keyed container fails
        }
        
        throw DecodingError.typeMismatch(GuitarNote.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Note must be an Int, a String, or a specificFret object."))
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .chordString(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .chordRoot(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .specificFret(let string, let fret):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("specificFret", forKey: .type)
            try container.encode(string, forKey: .string)
            try container.encode(fret, forKey: .fret)
        }
    }
}


struct PatternEvent: Codable, Hashable {
    let delay: String
    let notes: [GuitarNote]
    let delta: Double?
}

struct GuitarPattern: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let pattern: [PatternEvent]
}

typealias PatternLibrary = [String: [GuitarPattern]]

// MARK: - Configuration Models

struct PatternAssociation: Codable, Hashable {
    var patternId: String
    var measureIndices: [Double]?
}

struct ChordPerformanceConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var shortcut: String?
    var patternAssociations: [Shortcut: PatternAssociation]

    init(name: String, shortcut: String? = nil, patternAssociations: [Shortcut: PatternAssociation] = [:]) {
        self.name = name
        self.shortcut = shortcut
        self.patternAssociations = patternAssociations
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, shortcut, patternAssociations
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        
        // Try decoding the new format first
        if let associations = try? container.decodeIfPresent([String: PatternAssociation].self, forKey: .patternAssociations) {
            patternAssociations = [:]
            for (key, value) in associations {
                if let shortcut = Shortcut(stringValue: key) {
                    patternAssociations[shortcut] = value
                }
            }
        }
        // Fallback to decoding the old format for backward compatibility
        else if let oldAssociations = try? container.decodeIfPresent([String: String].self, forKey: .patternAssociations) {
            patternAssociations = [:]
            for (key, value) in oldAssociations {
                if let shortcut = Shortcut(stringValue: key) {
                    patternAssociations[shortcut] = PatternAssociation(patternId: value, measureIndices: nil)
                }
            }
        } else {
            patternAssociations = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        
        var associations: [String: PatternAssociation] = [:]
        for (key, value) in patternAssociations {
            associations[key.stringValue] = value
        }
        try container.encode(associations, forKey: .patternAssociations)
    }
}


enum QuantizationMode: String, Codable, CaseIterable {
    case none = "NONE"
    case measure = "MEASURE"
    case halfMeasure = "HALF_MEASURE"

    var displayName: String {
        switch self {
        case .none: return String(localized: "quantization_mode_none")
        case .measure: return String(localized: "quantization_mode_measure")
        case .halfMeasure: return String(localized: "quantization_mode_half_measure")
        }
    }
}

struct PerformanceConfig: Codable, Equatable {
    var tempo: Double
    var timeSignature: String
    var key: String
    var quantize: String?
    
    var chords: [ChordPerformanceConfig]
    var selectedDrumPatterns: [String]
    var selectedPlayingPatterns: [String]
    
    var activeDrumPatternId: String?
    var activePlayingPatternId: String?

    init(tempo: Double, timeSignature: String, key: String, quantize: String? = nil, chords: [ChordPerformanceConfig] = [], selectedDrumPatterns: [String] = [], selectedPlayingPatterns: [String] = [], activeDrumPatternId: String? = nil, activePlayingPatternId: String? = nil) {
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.key = key
        self.quantize = quantize
        self.chords = chords
        self.selectedDrumPatterns = selectedDrumPatterns
        self.selectedPlayingPatterns = selectedPlayingPatterns
        self.activeDrumPatternId = activeDrumPatternId
        self.activePlayingPatternId = activePlayingPatternId
    }
    
    enum CodingKeys: String, CodingKey {
        case tempo, timeSignature, key, quantize
        case chords, selectedDrumPatterns, selectedPlayingPatterns
        case activeDrumPatternId, activePlayingPatternId
        // Old keys for migration
        case patternGroups, drumPattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tempo = try container.decode(Double.self, forKey: .tempo)
        timeSignature = try container.decode(String.self, forKey: .timeSignature)
        key = try container.decode(String.self, forKey: .key)
        quantize = try container.decodeIfPresent(String.self, forKey: .quantize)

        // Migration logic for chords
        if let stringChords = try? container.decodeIfPresent([String].self, forKey: .chords) {
            self.chords = stringChords.map { ChordPerformanceConfig(name: $0) }
        } else if let configChords = try? container.decodeIfPresent([ChordPerformanceConfig].self, forKey: .chords) {
            self.chords = configChords
        } else {
            self.chords = []
        }

        selectedDrumPatterns = try container.decodeIfPresent([String].self, forKey: .selectedDrumPatterns) ?? []
        selectedPlayingPatterns = try container.decodeIfPresent([String].self, forKey: .selectedPlayingPatterns) ?? []
        activeDrumPatternId = try container.decodeIfPresent(String.self, forKey: .activeDrumPatternId)
        activePlayingPatternId = try container.decodeIfPresent(String.self, forKey: .activePlayingPatternId)

        // Migration for old preset format
        if let groups = try container.decodeIfPresent([OldPatternGroup].self, forKey: .patternGroups) {
            if self.chords.isEmpty {
                self.chords = groups.flatMap { $0.chordsOrder }.map { ChordPerformanceConfig(name: $0) }
            }
            if self.activePlayingPatternId == nil, let firstGroupPattern = groups.first?.pattern {
                self.activePlayingPatternId = firstGroupPattern
                if !self.selectedPlayingPatterns.contains(firstGroupPattern) {
                    self.selectedPlayingPatterns.append(firstGroupPattern)
                }
            }
        }
        
        if self.activeDrumPatternId == nil, let oldDrumPattern = try container.decodeIfPresent(String.self, forKey: .drumPattern) {
            self.activeDrumPatternId = oldDrumPattern
            if !self.selectedDrumPatterns.contains(oldDrumPattern) {
                self.selectedDrumPatterns.append(oldDrumPattern)
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tempo, forKey: .tempo)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(quantize, forKey: .quantize)
        try container.encode(chords, forKey: .chords)
        try container.encode(selectedDrumPatterns, forKey: .selectedDrumPatterns)
        try container.encode(selectedPlayingPatterns, forKey: .selectedPlayingPatterns)
        try container.encodeIfPresent(activeDrumPatternId, forKey: .activeDrumPatternId)
        try container.encodeIfPresent(activePlayingPatternId, forKey: .activePlayingPatternId)
    }
}

struct OldPatternGroup: Codable {
    var pattern: String?
    var chordsOrder: [String]
}


struct AppConfig: Codable, Equatable {
    let midiPortName: String
    let note: Int
    let velocity: Int
    let duration: Int
    let channel: Int
}

// MARK: - Preset Models

struct PresetInfo: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var createdAt: Date
    var updatedAt: Date
}

struct Preset: Codable, Equatable {
    let id: UUID
    var name: String
    var description: String?
    
    var performanceConfig: PerformanceConfig
    var appConfig: AppConfig
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, description: String? = nil, performanceConfig: PerformanceConfig, appConfig: AppConfig) {
        self.id = id
        self.name = name
        self.description = description
        self.performanceConfig = performanceConfig
        self.appConfig = appConfig
        self.createdAt = Date()
        self.updatedAt = Date()
    }



    enum CodingKeys: String, CodingKey {
        case id, name, description, performanceConfig, appConfig, createdAt, updatedAt
        case chordShortcuts // For migration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        performanceConfig = try container.decode(PerformanceConfig.self, forKey: .performanceConfig)
        appConfig = try container.decode(AppConfig.self, forKey: .appConfig)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Migration logic
        if let shortcutsToMigrate = try container.decodeIfPresent([String: Shortcut].self, forKey: .chordShortcuts) {
            for (chordName, shortcut) in shortcutsToMigrate {
                if let index = performanceConfig.chords.firstIndex(where: { $0.name == chordName }) {
                    performanceConfig.chords[index].shortcut = shortcut.stringValue
                }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(performanceConfig, forKey: .performanceConfig)
        try container.encode(appConfig, forKey: .appConfig)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    func toInfo() -> PresetInfo {
        return PresetInfo(id: self.id, name: self.name, description: self.description, createdAt: self.createdAt, updatedAt: self.updatedAt)
    }
}


// MARK: - Playing Mode

enum PlayingMode: String, CaseIterable {
    case manual = "手动"
    case assisted = "辅助"
    case automatic = "自动"

    var shortDisplay: String {
        switch self {
        case .manual: return "M"
        case .assisted: return "S"
        case .automatic: return "A"
        }
    }

    func next() -> PlayingMode {
        let all = PlayingMode.allCases
        if let idx = all.firstIndex(of: self) {
            return all[(idx + 1) % all.count]
        }
        return .manual
    }
}

// MARK: - Editor Data Models


struct DrumPatternEditorData: Identifiable {
    let id: String
    let timeSignature: String
    let pattern: DrumPattern
}

struct PlayingPatternEditorData: Identifiable {
    let id: String
    let timeSignature: String
    let pattern: GuitarPattern
}

// MARK: - Chord Playing Pattern Association Models

/// 快捷键冲突类型
enum ShortcutConflict: Equatable {
    case defaultChordShortcut
    case otherAssociation(chordName: String)
    case numericKey
    case systemShortcut
    
    var description: String {
        switch self {
        case .defaultChordShortcut:
            return "与和弦默认快捷键冲突"
        case .otherAssociation(let chordName):
            return "与和弦 \(chordName) 的演奏指法关联冲突"
        case .numericKey:
            return "与演奏指法切换数字键冲突"
        case .systemShortcut:
            return "与系统快捷键冲突"
        }
    }
}
