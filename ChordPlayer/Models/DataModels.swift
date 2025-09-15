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
    // Rows are instruments, columns are steps.
    var patternGrid: [[Bool]]
    var steps: Int
    var instruments: [String] // e.g., ["Kick", "Snare", "Hi-hat"]
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

    // Data Libraries (owned by the preset)
    var chords: [Chord]
    var playingPatterns: [GuitarPattern]
    var drumPatterns: [DrumPattern]
    
    // Currently active patterns
    var activePlayingPatternId: UUID?
    var activeDrumPatternId: UUID?

    init(id: UUID = UUID(),
         name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         bpm: Double = 120.0,
         timeSignature: TimeSignature = TimeSignature(),
         chordProgression: [String] = [],
         chords: [Chord] = [],
         playingPatterns: [GuitarPattern] = [],
         drumPatterns: [DrumPattern] = [],
         activePlayingPatternId: UUID? = nil,
         activeDrumPatternId: UUID? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.chordProgression = chordProgression
        self.chords = chords
        self.playingPatterns = playingPatterns
        self.drumPatterns = drumPatterns
        self.activePlayingPatternId = activePlayingPatternId
        self.activeDrumPatternId = activeDrumPatternId
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
