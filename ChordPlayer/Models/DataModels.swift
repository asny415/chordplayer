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

struct GuitarPattern: Codable, Identifiable, Hashable, Equatable {
    var id = UUID()
    var name: String
    // A 2D array of booleans representing a UI grid.
    // This simplification makes editing easier but is less nuanced than the previous event-based system.
    var patternGrid: [[Bool]]
    var steps: Int
    var strings: Int
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
