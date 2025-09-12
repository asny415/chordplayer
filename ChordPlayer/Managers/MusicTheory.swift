
import Foundation

struct MusicTheory {
    // A map from Chord Name to its default shortcut display string.
    // Used by the UI to show users what key to press.
    // Modifiers: ⇧ (Shift), ⌃ (Control), ⌥ (Option/Alt), ⌘ (Command)
    static let defaultChordToShortcutMap: [String: String] = {
        var map: [String: String] = [:]
        let baseNotes = ["A", "B", "C", "D", "E", "F", "G"]
        for note in baseNotes {
            let key = note.lowercased()
            map["\(note)_Major"] = key.uppercased()
            map["\(note)_Minor"] = "⇧+\(key.uppercased())"
            map["\(note)7"] = "⌃+\(key.uppercased())"
            map["\(note)_Major7"] = "⌘+\(key.uppercased())"
            map["\(note)_Minor7"] = "⌥+\(key.uppercased())"
        }
        return map
    }()

    // Standard guitar tuning in MIDI notes (E2, A2, D3, G3, B3, E4)
    // MIDI note numbers: C0 = 12, C1 = 24, C2 = 36, C3 = 48, C4 = 60, C5 = 72
    // E2 = 40, A2 = 45, D3 = 50, G3 = 55, B3 = 59, E4 = 64
    static let standardGuitarTuning: [Int] = [40, 45, 50, 55, 59, 64]

    static func chordToMidiNotes(chordDefinition: [Any], tuning: [Int]) -> [Int] {
        var midiNotes: [Int] = Array(repeating: -1, count: 6) // Initialize with -1 for muted strings
        for (index, fretValue) in chordDefinition.enumerated() {
            // Safely cast to StringOrInt
            if let stringOrInt = fretValue as? StringOrInt {
                switch stringOrInt {
                case .int(let fretInt):
                    let midiNote = tuning[index] + fretInt
                    midiNotes[index] = midiNote
                case .string(let s) where s == "x":
                    // Muted string, keep as -1
                    break
                default:
                    // Handle unexpected string values if necessary, or log an error
                    print("[MusicTheory] Warning: unexpected fret value: \(stringOrInt)")
                    break
                }
            } else {
                // Handle cases where fretValue is not a StringOrInt (shouldn't happen if data is consistent)
                print("[MusicTheory] Error: fret value not StringOrInt: \(fretValue)")
            }
        }
        return midiNotes
    }

    static func getChordFromDefaultMapping(key: JSKey) -> String? {
        let baseNote = key.name.uppercased()
        if !["A", "B", "C", "D", "E", "F", "G"].contains(baseNote) {
            return nil
        }

        if key.meta { return "\(baseNote)_Major7" }
        if key.alt { return "\(baseNote)_Minor7" }
        if key.ctrl { return "\(baseNote)7" }
        if key.shift { return "\(baseNote)_Minor" }

        return "\(baseNote)_Major"
    }

    static func getChordType(chordName: String) -> String {
        if chordName.hasSuffix("_Major7") { return "Major7" }
        if chordName.hasSuffix("_Minor7") { return "Minor7" }
        if chordName.hasSuffix("7") { return "7th" }
        if chordName.hasSuffix("_Major") { return "Major" }
        if chordName.hasSuffix("_Minor") { return "Minor" }
        return "Unknown"
    }

    static func getSectionName(groupIndex: Int) -> String {
        if groupIndex == 0 { return "intro" }
        if groupIndex == 1 { return "verse" }
        if groupIndex == 2 { return "chorus" }
        return "other"
    }

    static func getChordRootString(chordName: String, chordLibrary: ChordLibrary?) -> String {
        guard let frets = chordLibrary?[chordName] else {
            return "unknown_string"
        }

        // 6th string root check
        if case .int(_) = frets[0] {
            return "6th_string"
        }
        // 5th string root check
        if case .int(_) = frets[1] {
            return "5th_string"
        }
        // 4th string root check
        if case .int(_) = frets[2] {
            return "4th_string"
        }

        for i in (0...5).reversed() { // Iterate from high E to low E
            if case .int(_) = frets[i] {
                return "\(6 - i)th_string"
            }
        }
        return "unknown_string"
    }

    static func parseDelay(delayString: String) -> TimeInterval? {
        let components = delayString.split(separator: "/").map { String($0) }
        guard components.count == 2,
              let numerator = Double(components[0]),
              let denominator = Double(components[1]) else {
            return nil
        }
        // Assuming a quarter note is 1 beat, and 1 beat = 60/tempo seconds
        // This function will return a fraction of a beat.
        // The actual time interval will depend on the tempo, which is handled elsewhere.
        return numerator / denominator
    }

    static func parseTimeSignature(_ signature: String) -> (beats: Int, beatType: Int) {
        let components = signature.split(separator: "/").map { String($0) }
        guard components.count == 2,
              let beats = Int(components[0]),
              let beatType = Int(components[1]) else {
            return (4, 4) // Default to 4/4 if parsing fails
        }
        return (beats, beatType)
    }

    static func formatChordNameForDisplay(_ chordName: String) -> String {
        return chordName.replacingOccurrences(of: "_Sharp", with: "#")
                       .replacingOccurrences(of: "_", with: " ")
    }

    static func formatChordNameForDisplayAbbreviated(_ chordName: String) -> String {
        let components = chordName.split(separator: "_")
        
        // For simple names like "C" or "C_Sharp", just handle sharps.
        guard components.count >= 2 else {
            return chordName.replacingOccurrences(of: "_Sharp", with: "#")
        }

        let quality = String(components.last!)
        let noteParts = components.dropLast()
        let noteRaw = noteParts.joined(separator: "_")
        let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")

        switch quality {
        case "Major":
            return noteDisplay
        case "Minor":
            return noteDisplay + "m"
        default:
            // For other types like 7, Major7, etc., concatenate them without spaces.
            // e.g., "C_Sharp_7" -> "C#7"
            return chordName.replacingOccurrences(of: "_Sharp", with: "#").replacingOccurrences(of: "_", with: "")
        }
    }
}


// Helper struct to simulate the 'key' object from Node.js readline
struct JSKey {
    let name: String
    let meta: Bool // Corresponds to Command key on macOS
    let alt: Bool // Corresponds to Option key on macOS
    let ctrl: Bool // Corresponds to Control key on macOS
    let shift: Bool
}
