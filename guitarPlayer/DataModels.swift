import Foundation

// For chords.json
enum StringOrInt: Codable {
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
struct DrumPatternEvent: Codable {
    let delay: String
    let notes: [Int]
}

// New struct to hold pattern data and display name
struct DrumPattern: Codable {
    let displayName: String
    let pattern: [DrumPatternEvent] // The actual drum events

    // Provide custom CodingKeys for flexibility if JSON keys differ
    enum CodingKeys: String, CodingKey {
        case displayName
        case pattern
    }
}

// Updated DrumPatternLibrary type: TimeSignature -> PatternName -> DrumPattern
typealias DrumPatternLibrary = [String: [String: DrumPattern]]

// For patterns.json
enum StringOrDouble: Codable {
    case string(String)
    case int(Int)
    case double(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        if let x = try? container.decode(Int.self) { // Try Int first
            self = .int(x)
            return
        }
        if let x = try? container.decode(Double.self) { // Then Double
            self = .double(x)
            return
        }
        throw DecodingError.typeMismatch(StringOrDouble.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a String, Int, or Double"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x):
            try container.encode(x)
        case .int(let x):
            try container.encode(x)
        case .double(let x):
            try container.encode(x)
        }
    }
}

struct MusicPatternEvent: Codable {
    let delay: StringOrDouble
    let notes: [Int]
}

typealias PatternLibrary = [String: [MusicPatternEvent]]

// MARK: - Configuration Models

enum QuantizationMode: String, Codable, CaseIterable {
    case none = "NONE"
    case measure = "MEASURE"
    case halfMeasure = "HALF_MEASURE"
}

struct DrumSettings: Codable {
    let playKey: String
    let stopKey: String
    let defaultPattern: String
}

struct PatternGroup: Codable {
    var name: String
    var patterns: [String: String?] // String? to allow for null in JS
    // Ordered list of chord names added to this group (preserves display order)
    var chordsOrder: [String]
    // Per-chord metadata (fingering override, shortcut key)
    var chordAssignments: [String: ChordAssignment]

    init(name: String, patterns: [String: String?], chordsOrder: [String] = [], chordAssignments: [String: ChordAssignment] = [:]) {
        self.name = name
        self.patterns = patterns
        self.chordsOrder = chordsOrder
        self.chordAssignments = chordAssignments
    }

    // Provide backwards-compatible decoding if older data lacks new keys
    enum CodingKeys: String, CodingKey {
        case name
        case patterns
        case chordsOrder
        case chordAssignments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.patterns = try container.decode([String: String?].self, forKey: .patterns)
        self.chordsOrder = try container.decodeIfPresent([String].self, forKey: .chordsOrder) ?? []
        self.chordAssignments = try container.decodeIfPresent([String: ChordAssignment].self, forKey: .chordAssignments) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(patterns, forKey: .patterns)
        try container.encode(chordsOrder, forKey: .chordsOrder)
        try container.encode(chordAssignments, forKey: .chordAssignments)
    }
}

// Per-chord assignment metadata
struct ChordAssignment: Codable {
    var fingeringId: String?
    var shortcutKey: String?
}

struct PerformanceConfig: Codable {
    var tempo: Double
    var timeSignature: String
    var key: String
    var quantize: String? // Optional because it can be undefined in JS
    var quantizeToggleKey: String? // Optional
    
    var keyMap: [String: String] // Assuming keyMap is always present, can be empty
    var patternGroups: [PatternGroup]
}

struct AppConfig: Codable {
    let midiPortName: String
    let note: Int
    let velocity: Int
    let duration: Int
    let channel: Int
}
