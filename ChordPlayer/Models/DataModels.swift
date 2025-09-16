import Foundation
import SwiftUI

// MARK: - Core Data Models for Presets

struct Chord: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    // An array of 6 integers representing the fret for each string. -1 for muted string.
    var frets: [Int]
    // An array of 6 integers for finger positions. 0 for open string.
    var fingers: [Int]
}

// MARK: - Pattern Supporting Enums

enum NoteResolution: String, Codable, CaseIterable, Identifiable {
    case eighth = "8th Notes"
    case sixteenth = "16th Notes"
    var id: Self { self }
}

enum StepType: String, Codable, CaseIterable, Identifiable {
    case rest = "Rest"
    case arpeggio = "Arpeggio"
    case strum = "Strum"
    var id: Self { self }
}

enum StrumDirection: String, Codable, CaseIterable, Identifiable {
    case down = "Down"
    case up = "Up"
    var id: Self { self }
}

enum StrumSpeed: String, Codable, CaseIterable, Identifiable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"
    var id: Self { self }
}

// MARK: - Pattern Step Model

// Represents a single time step in a pattern (i.e., a column in the editor)
struct PatternStep: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    // Which strings are active in this step (0-5)
    var activeNotes: Set<Int> = []
    // The performance type for this step
    var type: StepType = .arpeggio
    // Strum parameters (only used when type is .strum)
    var strumDirection: StrumDirection = .down
    var strumSpeed: StrumSpeed = .medium
}

// MARK: - Guitar Pattern Model

struct GuitarPattern: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    
    // Defines the time value of each step
    var resolution: NoteResolution = .sixteenth
    
    // The sequence of steps that make up the pattern
    var steps: [PatternStep] = []
    
    // The total number of steps in the pattern
    var length: Int {
        didSet {
            guard length != oldValue else { return }
            let currentCount = steps.count
            if length > currentCount {
                steps.append(contentsOf: Array(repeating: PatternStep(), count: length - currentCount))
            } else if length < currentCount {
                steps = Array(steps.prefix(length))
            }
        }
    }
    
    init(id: UUID = UUID(), name: String, resolution: NoteResolution = .sixteenth, length: Int, steps: [PatternStep]? = nil) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.length = length
        
        if let providedSteps = steps, providedSteps.count == length {
            self.steps = providedSteps
        } else {
            // Initialize with empty steps if none are provided or if counts mismatch
            self.steps = Array(repeating: PatternStep(), count: length)
        }
    }
    
    // Add a custom decoder to handle the possibility of old data formats if necessary
    // For now, we assume new data structure.
    
    // Default initializer for creating a new pattern
    static func createNew(name: String, length: Int, resolution: NoteResolution) -> GuitarPattern {
        return GuitarPattern(name: name, resolution: resolution, length: length)
    }
    
    func generateAutomaticName() -> String {
        let resolutionStr = (resolution == .sixteenth) ? "16th" : "8th"
        let lengthStr = "\(length)s"
        
        let activeSteps = steps.filter { !$0.activeNotes.isEmpty }
        guard !activeSteps.isEmpty else {
            return "\(resolutionStr) \(lengthStr) Silent"
        }
        
        let strumCount = activeSteps.filter { $0.type == .strum }.count
        let arpCount = activeSteps.filter { $0.type == .arpeggio }.count
        
        let typeStr: String
        if strumCount > arpCount * 2 {
            typeStr = "Strum"
        } else if arpCount > strumCount * 2 {
            typeStr = "Arp"
        } else {
            typeStr = "Hybrid"
        }
        
        let rhythmIndices = steps.enumerated()
            .filter { !$0.element.activeNotes.isEmpty }
            .map { $0.offset + 1 }
            .prefix(4)
        
        let rhythmStr = rhythmIndices.map(String.init).joined(separator: "-")
        
        return "\(resolutionStr) \(lengthStr) \(typeStr) (\(rhythmStr))"
    }
}

struct DrumPattern: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var resolution: NoteResolution
    var instruments: [String]
    var midiNotes: [Int]

    // Rows are instruments, columns are steps.
    var patternGrid: [[Bool]]

    var length: Int {
        didSet {
            guard length != oldValue else { return }
            // Adjust the number of columns (steps) in the grid for each instrument
            for i in 0..<patternGrid.count {
                let currentCount = patternGrid[i].count
                if length > currentCount {
                    patternGrid[i].append(contentsOf: Array(repeating: false, count: length - currentCount))
                } else if length < currentCount {
                    patternGrid[i] = Array(patternGrid[i].prefix(length))
                }
            }
        }
    }

    init(id: UUID = UUID(), name: String, resolution: NoteResolution, length: Int, instruments: [String], midiNotes: [Int]) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.length = length
        self.instruments = instruments
        self.midiNotes = midiNotes
        self.patternGrid = Array(repeating: Array(repeating: false, count: length), count: instruments.count)
    }

    // Custom decoder to handle older data formats
    enum CodingKeys: String, CodingKey {
        case id, name, resolution, instruments, patternGrid, length, midiNotes, steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        resolution = try container.decodeIfPresent(NoteResolution.self, forKey: .resolution) ?? .sixteenth
        
        // Handle legacy `steps` property
        if let steps = try container.decodeIfPresent(Int.self, forKey: .steps) {
            length = steps
        } else {
            length = try container.decode(Int.self, forKey: .length)
        }
        
        instruments = try container.decodeIfPresent([String].self, forKey: .instruments) ?? ["Kick", "Snare", "Hi-hat"]
        patternGrid = try container.decode([[Bool]].self, forKey: .patternGrid)

        // Handle midiNotes, providing defaults if missing
        let defaultNotes = [36, 38, 42, 46, 49, 51]
        var decodedNotes = try container.decodeIfPresent([Int].self, forKey: .midiNotes) ?? []
        
        // Ensure midiNotes count matches instruments count
        if decodedNotes.count < instruments.count {
            for i in decodedNotes.count..<instruments.count {
                decodedNotes.append(defaultNotes[i % defaultNotes.count])
            }
        } else if decodedNotes.count > instruments.count {
            decodedNotes = Array(decodedNotes.prefix(instruments.count))
        }
        midiNotes = decodedNotes

        // Data integrity check
        if patternGrid.count != instruments.count || (patternGrid.first?.count ?? 0) != length {
            var correctedGrid = Array(repeating: Array(repeating: false, count: length), count: instruments.count)
            for i in 0..<min(patternGrid.count, instruments.count) {
                let row = patternGrid[i]
                for j in 0..<min(row.count, length) {
                    correctedGrid[i][j] = row[j]
                }
            }
            self.patternGrid = correctedGrid
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(instruments, forKey: .instruments)
        try container.encode(midiNotes, forKey: .midiNotes)
        try container.encode(patternGrid, forKey: .patternGrid)
        try container.encode(length, forKey: .length)
    }
}

struct TimeSignature: Codable, Hashable, Equatable {
    var beatsPerMeasure: Int = 4
    var beatUnit: Int = 4 // e.g., 4 for quarter note
}

// MARK: - The All-in-One Preset Document

struct Preset: Codable, Identifiable, Hashable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Settings
    var bpm: Double
    var timeSignature: TimeSignature
    var chordProgression: [String] // An array of chord names, e.g., ["Am", "G", "C"]
    var quantize: QuantizationMode = .none
    var key: String = "C"

    // Data Libraries (owned by the preset)
    var chords: [Chord]
    var playingPatterns: [GuitarPattern]
    var drumPatterns: [DrumPattern]
    var soloSegments: [SoloSegment] = []
    
    // Currently active patterns
    var activePlayingPatternId: UUID?
    var activeDrumPatternId: UUID?
    var activeSoloSegmentId: UUID?

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         bpm: Double = 120.0,
         timeSignature: TimeSignature = TimeSignature(),
         key: String = "C",
         chordProgression: [String] = [],
         chords: [Chord] = [],
         playingPatterns: [GuitarPattern] = [],
         drumPatterns: [DrumPattern] = [],
         soloSegments: [SoloSegment] = [],
         activePlayingPatternId: UUID? = nil,
         activeDrumPatternId: UUID? = nil,
         activeSoloSegmentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.key = key
        self.chordProgression = chordProgression
        self.chords = chords
        self.playingPatterns = playingPatterns
        self.drumPatterns = drumPatterns
        self.soloSegments = soloSegments
        self.activePlayingPatternId = activePlayingPatternId
        self.activeDrumPatternId = activeDrumPatternId
        self.activeSoloSegmentId = activeSoloSegmentId
    }
    
    static func createNew(name: String = "New Preset") -> Preset {
        return Preset(name: name)
    }
}

// MARK: - PresetInfo for list views
// This remains mostly the same, to allow for lazy loading of full presets.
struct PresetInfo: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
}

extension Preset {
    func toInfo() -> PresetInfo {
        return PresetInfo(id: self.id, name: self.name, createdAt: self.createdAt, updatedAt: self.updatedAt)
    }
}

// MARK: - Enums

enum QuantizationMode: String, Codable, CaseIterable, CustomStringConvertible {
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
    
    public var description: String { self.displayName }
}

enum PlayingMode: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case assisted = "Assisted"
    case automatic = "Automatic"
    
    var id: String { self.rawValue }
    
    var shortDisplay: String {
        switch self {
        case .manual: return "M"
        case .assisted: return "S"
        case .automatic: return "A"
        }
    }
}

// MARK: - Solo Models

struct SoloSegment: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var notes: [SoloNote] = []
    var lengthInBeats: Double = 4.0  // solo总长度（以拍为单位）
    
    init(name: String = "New Solo", lengthInBeats: Double = 4.0) {
        self.name = name
        self.lengthInBeats = lengthInBeats
    }
}

struct SoloNote: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var startTime: Double        // 开始时间（以拍为单位，相对于solo开始）
    var string: Int             // 弦（0-5，从高音弦到低音弦）
    var fret: Int               // 品位（0为空弦，-1为静音）
    var velocity: Int = 100     // 力度（0-127）
    var technique: PlayingTechnique = .normal
    var articulation: Articulation?
    
    init(startTime: Double, string: Int, fret: Int, velocity: Int = 100, technique: PlayingTechnique = .normal) {
        self.startTime = startTime
        self.string = string
        self.fret = fret
        self.velocity = velocity
        self.technique = technique
    }
}

enum PlayingTechnique: String, Codable, CaseIterable, Identifiable {
    case normal = "Normal"
    case slide = "Slide"
    case bend = "Bend"
    case vibrato = "Vibrato"
    case harmonics = "Harmonics"
    case mute = "Mute"
    case palmMute = "Palm Mute"
    
    var id: Self { self }
    
    var symbol: String {
        switch self {
        case .normal: return ""
        case .slide: return "/"
        case .bend: return "^"
        case .vibrato: return "~"
        case .harmonics: return "◇"
        case .mute: return "X"
        case .palmMute: return "PM"
        }
    }
}

struct Articulation: Codable, Hashable, Equatable {
    var bendAmount: Double = 0   // 推弦幅度（半音为单位）
    var slideTarget: Int?        // 滑音目标品位
    var vibratoIntensity: Double = 0  // 颤音强度（0-1）
}
