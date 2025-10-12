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
    // Override fret for a specific string, mapping stringIndex to fret.
    var fretOverrides: [Int: Int] = [:]
    // Store playing technique for a specific string.
    var techniques: [Int: PlayingTechnique] = [:]
    // The performance type for this step
    var type: StepType = .arpeggio
    // Strum parameters (only used when type is .strum)
    var strumDirection: StrumDirection = .down
    var strumSpeed: StrumSpeed = .medium
    
    // Default initializer to allow creating empty steps (e.g., PatternStep())
    init() {}

    enum CodingKeys: String, CodingKey {
        case id, activeNotes, fretOverrides, techniques, type, strumDirection, strumSpeed
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.activeNotes = try container.decodeIfPresent(Set<Int>.self, forKey: .activeNotes) ?? []
        self.fretOverrides = try container.decodeIfPresent([Int: Int].self, forKey: .fretOverrides) ?? [:]
        self.type = try container.decodeIfPresent(StepType.self, forKey: .type) ?? .arpeggio
        self.strumDirection = try container.decodeIfPresent(StrumDirection.self, forKey: .strumDirection) ?? .down
        self.strumSpeed = try container.decodeIfPresent(StrumSpeed.self, forKey: .strumSpeed) ?? .medium
        
        // Safely decode the new 'techniques' property, falling back to an empty dictionary if missing.
        self.techniques = try container.decodeIfPresent([Int: PlayingTechnique].self, forKey: .techniques) ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(activeNotes, forKey: .activeNotes)
        try container.encode(fretOverrides, forKey: .fretOverrides)
        try container.encode(techniques, forKey: .techniques)
        try container.encode(type, forKey: .type)
        try container.encode(strumDirection, forKey: .strumDirection)
        try container.encode(strumSpeed, forKey: .strumSpeed)
    }
}

enum GridResolution: String, Codable, CaseIterable, Identifiable {
    case eighth = "8th"
    case sixteenth = "16th"
    case eighthTriplet = "8th Triplet"
    case sixteenthTriplet = "16th Triplet"

    var id: Self { self }

    var stepsPerBeat: Int {
        switch self {
        case .eighth: return 2
        case .sixteenth: return 4
        case .eighthTriplet: return 3
        case .sixteenthTriplet: return 6
        }
    }
}

// MARK: - Guitar Pattern Model

struct GuitarPattern: Codable, Identifiable, Hashable, Equatable {
    var id: UUID
    var name: String
    
    // Defines the time value of each step
    var resolution: NoteResolution = .sixteenth // Legacy, for backward compatibility
    var resolutionNew: GridResolution? // New, flexible resolution
    
    // Computed property to safely access the active resolution
    var activeResolution: GridResolution {
        get {
            resolutionNew ?? (resolution == .sixteenth ? .sixteenth : .eighth)
        }
        set {
            resolutionNew = newValue
            // Also set the legacy property for basic backward compatibility
            if newValue == .sixteenth || newValue == .sixteenthTriplet {
                resolution = .sixteenth
            } else {
                resolution = .eighth
            }
        }
    }

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
    
    init(id: UUID = UUID(), name: String, resolution: GridResolution = .eighth, length: Int = 8, steps: [PatternStep]? = nil) {
        self.id = id
        self.name = name
        self.length = length
        self.steps = steps ?? Array(repeating: PatternStep(), count: length)
        self.activeResolution = resolution // This will set both new and legacy properties
    }
    
    // MARK: - Codable Implementation for Compatibility
    
    enum CodingKeys: String, CodingKey {
        case id, name, resolution, resolutionNew, steps, length
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        
        // Decode new resolution if available, otherwise fall back to legacy
        if let resNew = try container.decodeIfPresent(GridResolution.self, forKey: .resolutionNew) {
            self.resolutionNew = resNew
            self.resolution = (resNew == .sixteenth || resNew == .sixteenthTriplet) ? .sixteenth : .eighth
        } else {
            self.resolutionNew = nil // Explicitly nil for old data
            self.resolution = try container.decode(NoteResolution.self, forKey: .resolution)
        }
        
        self.length = try container.decode(Int.self, forKey: .length)
        self.steps = try container.decode([PatternStep].self, forKey: .steps)
        
        // Ensure steps count matches length
        if steps.count != length {
            let currentCount = steps.count
            if length > currentCount {
                steps.append(contentsOf: Array(repeating: PatternStep(), count: length - currentCount))
            } else if length < currentCount {
                steps = Array(steps.prefix(length))
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(length, forKey: .length)
        try container.encode(steps, forKey: .steps)
        
        // Save both properties for full compatibility
        try container.encode(resolution, forKey: .resolution)
        try container.encode(resolutionNew, forKey: .resolutionNew)
    }

    // Default initializer for creating a new pattern
    static func createNew(name: String, length: Int, resolution: GridResolution) -> GuitarPattern {
        return GuitarPattern(name: name, resolution: resolution, length: length)
    }
    
    func generateAutomaticName() -> String {
        let resolutionCode: String
        switch activeResolution {
        case .eighth:
            resolutionCode = "1"
        case .sixteenth:
            resolutionCode = "2"
        case .eighthTriplet:
            resolutionCode = "3"
        case .sixteenthTriplet:
            resolutionCode = "4"
        }

        let stepParts: [String] = steps.map { step in
            // Correct mapping: 0=e(1), 1=B(2), ..., 5=E(6). So, user-facing string number is model_index + 1.

            // A step is ONLY a rest if its type is explicitly .rest.
            if step.type == .rest {
                return "r"
            }

            // For other types, if there are no active notes, it's an empty column, not a rest.
            if step.activeNotes.isEmpty {
                return "" // Return an empty string to represent an empty, non-rest step.
            }

            switch step.type {
            case .arpeggio:
                let sortedActiveStrings = step.activeNotes.sorted()
                let arpeggioParts: [String] = sortedActiveStrings.map { stringIndex in
                    let stringNum = stringIndex + 1
                    if let fret = step.fretOverrides[stringIndex] {
                        return "\(stringNum)(\(fret))"
                    } else {
                        return "\(stringNum)"
                    }
                }
                return "a" + arpeggioParts.joined()

            case .strum:
                guard let minStringIndex = step.activeNotes.min(), let maxStringIndex = step.activeNotes.max() else { return "" } // Safety check

                var strumPart = "s"

                switch step.strumDirection {
                case .down:
                    strumPart += "d"
                case .up:
                    strumPart += "u"
                }

                if step.strumSpeed == .fast {
                    strumPart += "f"
                }

                // For down-strum, start is low-pitch (high index, e.g., 6th string/index 5)
                // For up-strum, start is high-pitch (low index, e.g., 1st string/index 0)
                let startString = step.strumDirection == .down ? maxStringIndex + 1 : minStringIndex + 1
                let endString = step.strumDirection == .down ? minStringIndex + 1 : maxStringIndex + 1

                strumPart += "\(startString)\(endString)"
                return strumPart

            case .rest: // Already handled above.
                return "r"
            }
        }

        return ([resolutionCode] + stepParts).joined(separator: "-")
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
    var capo: Int? = nil // Capo position (0 = no capo, 1 = 1st fret, etc.) - optional for backward compatibility

    // Data Libraries (owned by the preset)
    var chords: [Chord]
    var playingPatterns: [GuitarPattern]
    var drumPatterns: [DrumPattern]
    var soloSegments: [SoloSegment] = []
    var accompanimentSegments: [AccompanimentSegment] = []
    var melodicLyricSegments: [MelodicLyricSegment] = []

    // Song Arrangement - 歌曲编排功能
    var arrangement: SongArrangement = SongArrangement()

    // Currently active patterns
    var activePlayingPatternId: UUID?
    var activeDrumPatternId: UUID?
    var activeSoloSegmentId: UUID?
    var activeAccompanimentSegmentId: UUID?

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
         accompanimentSegments: [AccompanimentSegment] = [],
         melodicLyricSegments: [MelodicLyricSegment] = [],
         arrangement: SongArrangement = SongArrangement(),
         activePlayingPatternId: UUID? = nil,
         activeDrumPatternId: UUID? = nil,
         activeSoloSegmentId: UUID? = nil,
         activeAccompanimentSegmentId: UUID? = nil,
         capo: Int? = nil) {
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
        self.accompanimentSegments = accompanimentSegments
        self.melodicLyricSegments = melodicLyricSegments
        self.arrangement = arrangement
        self.activePlayingPatternId = activePlayingPatternId
        self.activeDrumPatternId = activeDrumPatternId
        self.activeSoloSegmentId = activeSoloSegmentId
        self.activeAccompanimentSegmentId = activeAccompanimentSegmentId
        self.capo = capo
    }
    
    static func createNew(name: String = "New Preset") -> Preset {
        return Preset(name: name)
    }
    
    // MARK: - Codable Implementation for Compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, bpm, timeSignature, chordProgression, quantize, key
        case chords, playingPatterns, drumPatterns, soloSegments, accompanimentSegments, melodicLyricSegments
        case arrangement, activePlayingPatternId, activeDrumPatternId, activeSoloSegmentId, activeAccompanimentSegmentId
        case capo
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        bpm = try container.decode(Double.self, forKey: .bpm)
        timeSignature = try container.decode(TimeSignature.self, forKey: .timeSignature)
        chordProgression = try container.decode([String].self, forKey: .chordProgression)
        quantize = try container.decodeIfPresent(QuantizationMode.self, forKey: .quantize) ?? .none
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? "C"
        chords = try container.decode([Chord].self, forKey: .chords)
        playingPatterns = try container.decode([GuitarPattern].self, forKey: .playingPatterns)
        drumPatterns = try container.decode([DrumPattern].self, forKey: .drumPatterns)
        soloSegments = try container.decodeIfPresent([SoloSegment].self, forKey: .soloSegments) ?? []
        accompanimentSegments = try container.decodeIfPresent([AccompanimentSegment].self, forKey: .accompanimentSegments) ?? []
        melodicLyricSegments = try container.decodeIfPresent([MelodicLyricSegment].self, forKey: .melodicLyricSegments) ?? []
        arrangement = try container.decodeIfPresent(SongArrangement.self, forKey: .arrangement) ?? SongArrangement()
        activePlayingPatternId = try container.decodeIfPresent(UUID.self, forKey: .activePlayingPatternId)
        activeDrumPatternId = try container.decodeIfPresent(UUID.self, forKey: .activeDrumPatternId)
        activeSoloSegmentId = try container.decodeIfPresent(UUID.self, forKey: .activeSoloSegmentId)
        activeAccompanimentSegmentId = try container.decodeIfPresent(UUID.self, forKey: .activeAccompanimentSegmentId)
        capo = try container.decodeIfPresent(Int.self, forKey: .capo)  // Optional - defaults to nil for backward compatibility
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(timeSignature, forKey: .timeSignature)
        try container.encode(chordProgression, forKey: .chordProgression)
        try container.encode(quantize, forKey: .quantize)
        try container.encode(key, forKey: .key)
        try container.encode(chords, forKey: .chords)
        try container.encode(playingPatterns, forKey: .playingPatterns)
        try container.encode(drumPatterns, forKey: .drumPatterns)
        try container.encode(soloSegments, forKey: .soloSegments)
        try container.encode(accompanimentSegments, forKey: .accompanimentSegments)
        try container.encode(melodicLyricSegments, forKey: .melodicLyricSegments)
        try container.encode(arrangement, forKey: .arrangement)
        try container.encodeIfPresent(activePlayingPatternId, forKey: .activePlayingPatternId)
        try container.encodeIfPresent(activeDrumPatternId, forKey: .activeDrumPatternId)
        try container.encodeIfPresent(activeSoloSegmentId, forKey: .activeSoloSegmentId)
        try container.encodeIfPresent(activeAccompanimentSegmentId, forKey: .activeAccompanimentSegmentId)
        try container.encodeIfPresent(capo, forKey: .capo)
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
    var duration: Double?       // new property to store the note's duration in beats
    var string: Int             // 弦（0-5，从高音弦到低音弦）
    var fret: Int               // 品位（0为空弦，-1为静音）
    var velocity: Int = 100     // 力度（0-127）
    var technique: PlayingTechnique = .normal
    var articulation: Articulation?
    
    init(startTime: Double, duration: Double? = nil, string: Int, fret: Int, velocity: Int = 100, technique: PlayingTechnique = .normal) {
        self.startTime = startTime
        self.duration = duration
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
    case pullOff = "Pull-off"

    var id: Self { self }

    var chineseName: String {
        switch self {
        case .normal: return "普通"
        case .slide: return "滑音"
        case .bend: return "推弦"
        case .vibrato: return "颤音"
        case .pullOff: return "勾弦"
        }
    }
    
    var symbol: String {
        switch self {
        case .normal: return ""
        case .slide: return "/"
        case .bend: return "^"
        case .vibrato: return "~"
        case .pullOff: return "p"
        }
    }
}

struct Articulation: Codable, Hashable, Equatable {
    var bendAmount: Double = 0   // 推弦幅度（半音为单位）
    var slideTarget: Int?        // 滑音目标品位
    var vibratoIntensity: Double = 0  // 颤音强度（0-1）
}

// MARK: - Accompaniment Models

/// Represents a single, resizable event on the timeline for a chord or a pattern.
struct TimelineEvent: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    /// The ID of the `Chord` or `GuitarPattern` this event refers to.
    var resourceId: UUID
    /// The beat on which this event starts within its measure.
    var startBeat: Int
    /// The duration of this event in beats.
    var durationInBeats: Int
}

/// A measure in an accompaniment segment, containing two tracks of timeline events.
struct AccompanimentMeasure: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var chordEvents: [TimelineEvent] = []
    var patternEvents: [TimelineEvent] = []
    var dynamics: MeasureDynamics = .medium

    init() {}
}

/// A segment of accompaniment, composed of multiple measures.
struct AccompanimentSegment: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var lengthInMeasures: Int
    var measures: [AccompanimentMeasure]

    init(name: String = "New Accompaniment", lengthInMeasures: Int = 4) {
        self.name = name
        self.lengthInMeasures = lengthInMeasures
        self.measures = Array(repeating: AccompanimentMeasure(), count: lengthInMeasures)
    }

    mutating func updateLength(_ newLength: Int) {
        guard newLength != lengthInMeasures else { return }
        lengthInMeasures = newLength

        if newLength > measures.count {
            measures.append(contentsOf: Array(repeating: AccompanimentMeasure(), count: newLength - measures.count))
        } else if newLength < measures.count {
            measures = Array(measures.prefix(newLength))
        }
    }

    func generateAutomaticName(using preset: Preset) -> String {
        let allChordEvents = measures.flatMap { $0.chordEvents }.sorted { $0.startBeat < $1.startBeat }
        
        let chordNames: [String] = allChordEvents.compactMap { event in
            preset.chords.first { $0.id == event.resourceId }?.name
        }

        let uniqueChords = chordNames.removingDuplicates().prefix(4)
        let progression = uniqueChords.joined(separator: "→")

        if progression.isEmpty {
            return name
        } else {
            return "\(name) (\(progression))"
        }
    }
}

// Dynamics enum remains the same
enum MeasureDynamics: String, Codable, CaseIterable, CustomStringConvertible, Identifiable {
    case soft = "Soft"
    case medium = "Medium"
    case loud = "Loud"

    var id: Self { self }
    var description: String { rawValue }

    var velocityMultiplier: Double {
        switch self {
        case .soft: return 0.7
        case .medium: return 1.0
        case .loud: return 1.3
        }
    }

    var displaySymbol: String {
        switch self {
        case .soft: return "p"
        case .medium: return "mf"
        case .loud: return "f"
        }
    }
}


// MARK: - Song Arrangement Models

struct SongArrangement: Codable, Hashable, Equatable {
    var lengthInBeats: Double = 16.0 // 歌曲编排总长度（拍数）

    // 各种轨道
    var drumTrack: DrumTrack = DrumTrack()
    var guitarTracks: [GuitarTrack] = []
    var annotationTrack: AnnotationTrack = AnnotationTrack()
    var lyricsTracks: [LyricsTrack] = []

    var lastModified: Date = Date()

    init() {
        // 默认添加一条吉他轨道
        self.guitarTracks.append(GuitarTrack(name: "Guitar 1"))
    }

    mutating func updateLength(_ newLength: Double) {
        guard newLength > 0 else { return }
        lengthInBeats = newLength
        lastModified = Date()
    }

    mutating func addGuitarTrack() {
        let newTrack = GuitarTrack(name: "Guitar \(guitarTracks.count + 1)")
        guitarTracks.append(newTrack)
        lastModified = Date()
    }

    mutating func removeGuitarTrack(withId id: UUID) {
        guitarTracks.removeAll { $0.id == id }
        lastModified = Date()
    }
    
    mutating func addLyricsTrack() {
        let newTrack = LyricsTrack(name: "Lyrics \(lyricsTracks.count + 1)")
        lyricsTracks.append(newTrack)
        lastModified = Date()
    }

    mutating func removeLyricsTrack(withId id: UUID) {
        lyricsTracks.removeAll { $0.id == id }
        lastModified = Date()
    }
}

// MARK: - Drum Track Models

struct DrumTrack: Codable, Hashable, Equatable {
    var segments: [DrumSegment] = []
    var isMuted: Bool = false
    var volume: Double = 1.0
    var midiChannel: Int?

    mutating func addSegment(_ segment: DrumSegment) {
        // 确保不重叠
        segments.removeAll { existing in
            existing.startBeat < segment.startBeat + segment.durationInBeats &&
            existing.startBeat + existing.durationInBeats > segment.startBeat
        }
        segments.append(segment)
        segments.sort { $0.startBeat < $1.startBeat }
    }
}

struct DrumSegment: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var startBeat: Double
    var durationInBeats: Double
    var patternId: UUID // 引用Preset中的DrumPattern

    init(startBeat: Double, durationInBeats: Double, patternId: UUID) {
        self.startBeat = startBeat
        self.durationInBeats = durationInBeats
        self.patternId = patternId
    }
}

// MARK: - Guitar Track Models

struct GuitarTrack: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var segments: [GuitarSegment] = []
    var isMuted: Bool = false
    var isSolo: Bool = false
    var volume: Double = 1.0
    var pan: Double = 0.0 // -1.0 (左) 到 1.0 (右)
    var midiChannel: Int?
    var capo: Int?

    init(name: String) {
        self.name = name
    }

    mutating func addSegment(_ segment: GuitarSegment) {
        // 允许重叠，按开始时间排序
        segments.append(segment)
        segments.sort { $0.startBeat < $1.startBeat }
    }

    mutating func removeSegment(withId id: UUID) {
        segments.removeAll { $0.id == id }
    }
}

struct GuitarSegment: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var startBeat: Double
    var durationInBeats: Double
    var type: GuitarSegmentType

    init(startBeat: Double, durationInBeats: Double, type: GuitarSegmentType) {
        self.startBeat = startBeat
        self.durationInBeats = durationInBeats
        self.type = type
    }
}

enum GuitarSegmentType: Codable, Hashable, Equatable {
    case solo(segmentId: UUID)
    case accompaniment(segmentId: UUID)

    var segmentId: UUID {
        switch self {
        case .solo(let id): return id
        case .accompaniment(let id): return id
        }
    }

    var displayName: String {
        switch self {
        case .solo: return "Solo"
        case .accompaniment: return "Accompaniment"
        }
    }
}

// MARK: - Annotation Track Models

struct AnnotationTrack: Codable, Hashable, Equatable {
    var annotations: [Annotation] = []
    var isVisible: Bool = true

    mutating func addAnnotation(_ annotation: Annotation) {
        annotations.append(annotation)
        annotations.sort { $0.startBeat < $1.startBeat }
    }

    mutating func removeAnnotation(withId id: UUID) {
        annotations.removeAll { $0.id == id }
    }
}

struct Annotation: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var startBeat: Double
    var text: String
    var type: AnnotationType = .chord
    var color: String = "blue" // 颜色标识

    init(startBeat: Double, text: String, type: AnnotationType = .chord) {
        self.startBeat = startBeat
        self.text = text
        self.type = type
        self.color = type.defaultColor
    }
}

enum AnnotationType: String, Codable, CaseIterable, Hashable, Equatable, Identifiable {
    case chord = "和弦"
    case scaleNote = "音阶"
    case marker = "标记"
    case structure = "结构" // 如：Verse, Chorus, Bridge

    var id: Self { self }

    var defaultColor: String {
        switch self {
        case .chord: return "blue"
        case .scaleNote: return "green"
        case .marker: return "orange"
        case .structure: return "purple"
        }
    }

    var systemImageName: String {
        switch self {
        case .chord: return "music.note"
        case .scaleNote: return "tuningfork"
        case .marker: return "flag.fill"
        case .structure: return "building.columns.fill"
        }
    }
}

// MARK: - Lyrics Track Models

struct LyricsTrack: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    var lyrics: [LyricsSegment] = []
    var isMuted: Bool = false
    var volume: Double = 1.0
    var fontSize: Double = 14.0
    var midiChannel: Int?

    init(name: String) {
        self.name = name
    }
    
    mutating func addLyrics(_ lyrics: LyricsSegment) {
        self.lyrics.append(lyrics)
        self.lyrics.sort { $0.startBeat < $1.startBeat }
    }

    mutating func removeLyrics(withId id: UUID) {
        lyrics.removeAll { $0.id == id }
    }
}

struct LyricsSegment: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var melodicLyricSegmentId: UUID? // References the MelodicLyricSegment this lyrics segment represents
    var startBeat: Double
    var durationInBeats: Double
    var text: String
    var language: String = "zh" // 支持多语言歌词

    init(id: UUID = UUID(), melodicLyricSegmentId: UUID? = nil, startBeat: Double, durationInBeats: Double, text: String, language: String = "zh") {
        self.id = id
        self.melodicLyricSegmentId = melodicLyricSegmentId
        self.startBeat = startBeat
        self.durationInBeats = durationInBeats
        self.text = text
        self.language = language
    }
}

// MARK: - Melodic Lyric Models

/// 代表歌词中的一个字或词及其音乐属性
struct MelodicLyricItem: Identifiable, Codable, Hashable {
    /// 唯一标识符
    var id = UUID()
    
    /// 歌词文字，可以为空字符串表示休止或间奏
    var word: String
    
    /// 段内位置，以 ticks 为单位的偏移量 (1拍 = 12 ticks)
    var positionInTicks: Int
    
    /// 持续时间，以 ticks 为单位
    var durationInTicks: Int?
    
    /// 音高 (1-7 分别代表 Do, Re, Mi, Fa, Sol, La, Si)。0可以用来表示休止。
    var pitch: Int
    
    /// 八度偏移量 (-2, -1, 0, 1, 2)
    var octave: Int
    
    /// 音高偏移，单位为半音。nil 表示无偏移。1 为升半音(#)，-1 为降半音(b)。
    var pitchOffset: Int?
    
    /// 可选的演奏技巧 (复用已有的 PlayingTechnique 枚举)
    var technique: PlayingTechnique?
    
    // MARK: - Legacy Properties (for migration)
    private var position: Int?
    private var duration: Int?
    
    init(id: UUID = UUID(), word: String, positionInTicks: Int, durationInTicks: Int? = nil, pitch: Int, octave: Int, technique: PlayingTechnique? = nil) {
        self.id = id
        self.word = word
        self.positionInTicks = positionInTicks
        self.durationInTicks = durationInTicks
        self.pitch = pitch
        self.octave = octave
        self.technique = technique
    }
    
    // MARK: - Codable Implementation for Compatibility
    
    enum CodingKeys: String, CodingKey {
        case id, word, positionInTicks, durationInTicks, pitch, octave, technique
        case position, duration // Legacy keys
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.word = try container.decode(String.self, forKey: .word)
        self.pitch = try container.decode(Int.self, forKey: .pitch)
        self.octave = try container.decode(Int.self, forKey: .octave)
        self.technique = try container.decodeIfPresent(PlayingTechnique.self, forKey: .technique)

        // Check for new tick-based properties first
        if let posTicks = try container.decodeIfPresent(Int.self, forKey: .positionInTicks) {
            self.positionInTicks = posTicks
            self.durationInTicks = try container.decodeIfPresent(Int.self, forKey: .durationInTicks)
        } else {
            // Fallback to legacy 16th-note based properties and convert them
            let legacyPosition = try container.decode(Int.self, forKey: .position)
            let legacyDuration = try container.decodeIfPresent(Int.self, forKey: .duration)
            
            // Conversion: 1 16th note step = 3 ticks (assuming 1 beat = 12 ticks)
            self.positionInTicks = legacyPosition * 3
            self.durationInTicks = legacyDuration.map { $0 * 3 }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(pitch, forKey: .pitch)
        try container.encode(octave, forKey: .octave)
        try container.encodeIfPresent(technique, forKey: .technique)
        
        // Always encode the new tick-based properties
        try container.encode(positionInTicks, forKey: .positionInTicks)
        try container.encodeIfPresent(durationInTicks, forKey: .durationInTicks)
    }
}

/// 代表一个完整的旋律歌词片段
struct MelodicLyricSegment: Identifiable, Codable, Hashable, Equatable {
    /// 唯一标识符
    var id = UUID()
    
    /// 片段名称，例如 "Verse 1", "Chorus"
    var name: String
    
    /// 片段的小节数，例如 2, 4, 8
    var lengthInBars: Int
    
    /// 网格量化单位
    var resolution: GridResolution?
    
    /// 组成该片段的歌词单元数组
    var items: [MelodicLyricItem]

    // Legacy property for migration
    private var gridUnit: Int?

    var activeResolution: GridResolution {
        get { resolution ?? .sixteenth } // Default to 16th if not set
        set { resolution = newValue }
    }

    init(id: UUID = UUID(), name: String, lengthInBars: Int, resolution: GridResolution? = .sixteenth, items: [MelodicLyricItem] = []) {
        self.id = id
        self.name = name
        self.lengthInBars = lengthInBars
        self.resolution = resolution
        self.items = items
    }
    
    // MARK: - Codable Implementation for Compatibility
    
    enum CodingKeys: String, CodingKey {
        case id, name, lengthInBars, resolution, items, gridUnit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.lengthInBars = try container.decode(Int.self, forKey: .lengthInBars)
        self.items = try container.decode([MelodicLyricItem].self, forKey: .items)

        // Decode new resolution if available, otherwise fall back to legacy gridUnit
        if let res = try container.decodeIfPresent(GridResolution.self, forKey: .resolution) {
            self.resolution = res
        } else if let legacyGridUnit = try container.decodeIfPresent(Int.self, forKey: .gridUnit) {
            // The old `gridUnit` was the number of 16th-note steps in the grid snap.
            // 1 = 16th grid, 2 = 8th grid.
            switch legacyGridUnit {
            case 1: self.resolution = .sixteenth
            case 2: self.resolution = .eighth
            default: self.resolution = .sixteenth // Safest fallback for other values
            }
        } else {
            self.resolution = .sixteenth // Default for very old data without any grid info
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lengthInBars, forKey: .lengthInBars)
        try container.encode(items, forKey: .items)
        // Always encode the new resolution property
        try container.encode(resolution, forKey: .resolution)
    }
}

// Helper extension to get unique elements while preserving order
extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var addedDict = [Element: Bool]()
        return filter {
            addedDict.updateValue(true, forKey: $0) == nil
        }
    }
}
