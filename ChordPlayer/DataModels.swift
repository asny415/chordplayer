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
    let delay: String
    let notes: [Int]
}

struct DrumPattern: Codable, Hashable {
    let displayName: String
    let pattern: [DrumPatternEvent]

    enum CodingKeys: String, CodingKey {
        case displayName
        case pattern
    }
}

typealias DrumPatternLibrary = [String: [String: DrumPattern]]

// For patterns.json
typealias NoteValue = StringOrInt

struct PatternEvent: Codable, Hashable {
    let delay: String
    let notes: [NoteValue]
    let delta: Double?
}

struct GuitarPattern: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let pattern: [PatternEvent]
}

typealias PatternLibrary = [String: [GuitarPattern]]

// MARK: - Configuration Models

enum QuantizationMode: String, Codable, CaseIterable {
    case none = "NONE"
    case measure = "MEASURE"
    case halfMeasure = "HALF_MEASURE"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .measure: return "Measure"
        case .halfMeasure: return "Half Measure"
        }
    }
}

struct PerformanceConfig: Codable, Equatable {
    var tempo: Double
    var timeSignature: String
    var key: String
    var quantize: String?
    
    var chords: [String]
    var selectedDrumPatterns: [String]
    var selectedPlayingPatterns: [String]
    
    var activeDrumPatternId: String?
    var activePlayingPatternId: String?

    init(tempo: Double, timeSignature: String, key: String, quantize: String? = nil, chords: [String] = [], selectedDrumPatterns: [String] = [], selectedPlayingPatterns: [String] = [], activeDrumPatternId: String? = nil, activePlayingPatternId: String? = nil) {
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

        chords = try container.decodeIfPresent([String].self, forKey: .chords) ?? []
        selectedDrumPatterns = try container.decodeIfPresent([String].self, forKey: .selectedDrumPatterns) ?? []
        selectedPlayingPatterns = try container.decodeIfPresent([String].self, forKey: .selectedPlayingPatterns) ?? []
        activeDrumPatternId = try container.decodeIfPresent(String.self, forKey: .activeDrumPatternId)
        activePlayingPatternId = try container.decodeIfPresent(String.self, forKey: .activePlayingPatternId)

        if let groups = try container.decodeIfPresent([OldPatternGroup].self, forKey: .patternGroups) {
            if self.chords.isEmpty {
                self.chords = groups.flatMap { $0.chordsOrder }
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
    
    func toInfo() -> PresetInfo {
        return PresetInfo(id: self.id, name: self.name, description: self.description, createdAt: self.createdAt, updatedAt: self.updatedAt)
    }
}
