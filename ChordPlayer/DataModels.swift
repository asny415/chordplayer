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
// Represents a value in the "notes" array, which can be a string like "ROOT" or an int for a physical string.
typealias NoteValue = StringOrInt

struct PatternEvent: Codable, Hashable {
    let delay: String
    let notes: [NoteValue]
    let delta: Double? // Optional delta for strumming

    // Implementing Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(delay)
        // NoteValue is not hashable by default, need to handle it.
        // For simplicity, we can combine hashes of string/int representations.
        for note in notes {
            switch note {
            case .string(let s):
                hasher.combine(s)
            case .int(let i):
                hasher.combine(i)
            }
        }
        hasher.combine(delta)
    }

    static func == (lhs: PatternEvent, rhs: PatternEvent) -> Bool {
        return lhs.delay == rhs.delay && lhs.notes.count == rhs.notes.count && lhs.delta == rhs.delta // Simplified equality
    }
}

struct GuitarPattern: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let pattern: [PatternEvent]

    // Implementing Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(pattern)
    }

    static func == (lhs: GuitarPattern, rhs: GuitarPattern) -> Bool {
        return lhs.id == rhs.id
    }
}

// The library is a dictionary from Time Signature (e.g., "4/4") to a list of patterns.
typealias PatternLibrary = [String: [GuitarPattern]]

// Keep MusicPatternEvent for other parts of the app that might use it, e.g., the simple preview player.
// But we need to make it compatible with the old structure if needed.
struct MusicPatternEvent: Codable {
    let delay: StringOrDouble
    let notes: [Int]
}

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

struct DrumSettings: Codable {
    let playKey: String
    let stopKey: String
    let defaultPattern: String
}

struct PatternGroup: Codable, Equatable {
    var name: String
    var patterns: [String: String?] // String? to allow for null in JS
    var pattern: String? // New field for default fingering ID
    // Ordered list of chord names added to this group (preserves display order)
    var chordsOrder: [String]
    // Per-chord metadata (fingering override, shortcut key)
    var chordAssignments: [String: ChordAssignment]

    init(name: String, patterns: [String: String?], pattern: String? = nil, chordsOrder: [String] = [], chordAssignments: [String: ChordAssignment] = [:]) {
        self.name = name
        self.patterns = patterns
        self.pattern = pattern // Initialize new field
        self.chordsOrder = chordsOrder
        self.chordAssignments = chordAssignments
    }

    // Provide backwards-compatible decoding if older data lacks new keys
    enum CodingKeys: String, CodingKey {
        case name
        case patterns
        case pattern // Add new field to CodingKeys
        case chordsOrder
        case chordAssignments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.patterns = try container.decode([String: String?].self, forKey: .patterns)
        self.pattern = try container.decodeIfPresent(String.self, forKey: .pattern) // Decode new field
        self.chordsOrder = try container.decodeIfPresent([String].self, forKey: .chordsOrder) ?? []
        self.chordAssignments = try container.decodeIfPresent([String: ChordAssignment].self, forKey: .chordAssignments) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(patterns, forKey: .patterns)
        try container.encodeIfPresent(pattern, forKey: .pattern) // Encode new field
        try container.encode(chordsOrder, forKey: .chordsOrder)
        try container.encode(chordAssignments, forKey: .chordAssignments)
    }
}

// Per-chord assignment metadata
struct ChordAssignment: Codable, Equatable {
    var fingeringId: String?
    var shortcutKey: String?
}

struct PerformanceConfig: Codable, Equatable {
    var tempo: Double
    var timeSignature: String
    var key: String
    var quantize: String? // Optional because it can be undefined in JS
    var quantizeToggleKey: String? // Optional
    var drumPattern: String?

    var keyMap: [String: String] // Assuming keyMap is always present, can be empty
    var patternGroups: [PatternGroup]
}

struct AppConfig: Codable, Equatable {
    let midiPortName: String
    let note: Int
    let velocity: Int
    let duration: Int
    let channel: Int
}
