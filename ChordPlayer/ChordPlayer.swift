import Foundation
import Combine

class ChordPlayer: ObservableObject {
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData

    private var playingNotes: [UInt8: UUID] = [:] // Maps MIDI Note -> Scheduled Note-Off Task ID
    private var stringNotes: [Int: UInt8] = [:] // Maps String Index (0-5) -> MIDI Note

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome // Metronome is injected but not used in this snippet, kept for context
        self.appData = appData
    }

    func playChord(chordName: String, pattern: GuitarPattern, tempo: Double = 120.0, key: String = "C", capo: Int = 0, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        guard let chordDefinition = appData.chordLibrary?[chordName] else {
            print("[ChordPlayer] Chord definition for \(chordName) not found.")
            return
        }

        var transposeOffset = 0
        if let idx = appData.KEY_CYCLE.firstIndex(of: key) {
            transposeOffset = idx
        }

        var midiNotes: [Int] = Array(repeating: -1, count: 6)
        for (i, fretVal) in chordDefinition.enumerated() {
            switch fretVal {
            case .int(let fretInt):
                if fretInt >= 0 { // Consider 'x' or negative as muted
                    midiNotes[i] = MusicTheory.standardGuitarTuning[i] + fretInt + transposeOffset + capo
                }
            case .string:
                midiNotes[i] = -1
            }
        }

        let _: [Int] = midiNotes.filter { $0 != -1 }
        
        panic() // Stop previous notes before playing new ones

        let wholeNoteSeconds = (60.0 / tempo) * 4.0
        let schedulingStartUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0

        for event in pattern.pattern {
            guard let delayFraction = MusicTheory.parseDelay(delayString: event.delay) else {
                print("[ChordPlayer] Could not parse delay string: \(event.delay)")
                continue
            }
            let eventBaseTimeMs = schedulingStartUptimeMs + (delayFraction * wholeNoteSeconds * 1000.0)

            var notesToSchedule: [(note: UInt8, stringIndex: Int)] = []
            
            // Filter out notes that are on muted strings based on the current chord definition
            let filteredPatternNotes = event.notes.filter { noteValue in
                switch noteValue {
                case .int(let stringNumber): // This is a direct string number (1-6)
                    let stringIndex = stringNumber - 1 // Convert to 0-5 index
                    // Only include if the string index is valid and the MIDI note for that string is not -1 (i.e., not muted)
                    return stringIndex >= 0 && stringIndex < midiNotes.count && midiNotes[stringIndex] != -1
                case .string(let symbol):
                    // For "ROOT" notes, we need to check if the *resolved* string will be muted.
                    // This is more complex as it depends on the rootStringIndex and offset.
                    // For now, we'll allow ROOT notes to pass through this filter and handle muting
                    // when resolving the actual MIDI note, as it's already done there.
                    // The primary concern is direct string numbers.
                    return symbol.starts(with: "ROOT") // Allow ROOT notes to be processed further
                }
            }

            // Find the root string and its MIDI note
            var rootInfo: (stringIndex: Int, midiNote: Int)?
            for (index, note) in midiNotes.enumerated() {
                if note != -1 {
                    rootInfo = (stringIndex: index, midiNote: note)
                    break
                }
            }

            guard let unwrappedRootInfo = rootInfo else {
                print("[ChordPlayer] Could not determine root note for chord \(chordName).")
                return // Cannot proceed without a root note
            }
            let unwrappedRootStringIndex = unwrappedRootInfo.stringIndex
            let _ = unwrappedRootInfo.midiNote

            for noteValue in filteredPatternNotes { // Iterate over filtered notes
                var resolvedNote: (note: Int, stringIndex: Int)?

                switch noteValue {
                case .int(let stringNumber): // This is a direct string number (1-6)
                    let stringIndex = stringNumber - 1 // Convert to 0-5 index
                    if stringIndex >= 0 && stringIndex < midiNotes.count && midiNotes[stringIndex] != -1 {
                        resolvedNote = (note: midiNotes[stringIndex], stringIndex: stringIndex)
                    }
                case .string(let symbol):
                    if symbol.starts(with: "ROOT") {
                        let numPart = symbol.replacingOccurrences(of: "ROOT", with: "").replacingOccurrences(of: "-", with: "")
                        var offset: Int = 0 // Offset from the root string
                        if !numPart.isEmpty, let num = Int(numPart) {
                            offset = num
                        }
                        
                        let targetStringIndex = unwrappedRootStringIndex + offset
                        
                        // Ensure targetStringIndex is within valid bounds (0-5)
                        if targetStringIndex >= 0 && targetStringIndex < midiNotes.count {
                            let note = midiNotes[targetStringIndex]
                            if note != -1 {
                                resolvedNote = (note: note, stringIndex: targetStringIndex)
                            } else {
                                print("[ChordPlayer] Warning: Pattern requested note on muted string at index \(targetStringIndex) (ROOT+\(offset)).")
                            }
                        } else {
                            print("[ChordPlayer] Warning: Pattern requested note on string index \(targetStringIndex) (ROOT+\(offset)) which is out of bounds.")
                        }
                    } else {
                        // Handle other string symbols if any, or log an error
                        print("[ChordPlayer] Warning: Unrecognized string symbol in pattern: \(symbol)")
                    }
                }
                
                if let note = resolvedNote {
                    notesToSchedule.append((note: UInt8(note.note), stringIndex: note.stringIndex))
                }
            }

            for (i, item) in notesToSchedule.enumerated() {
                var strumOffsetMs: Double = 0
                if let delta = event.delta {
                    strumOffsetMs = delta * Double(i)
                }

                let scheduledNoteOnUptimeMs = eventBaseTimeMs + strumOffsetMs
                
                // If a note is already playing on this string, cancel its scheduled note-off and send an immediate note-off.
                if let previousNote = self.stringNotes[item.stringIndex] {
                    if let scheduledOffId = self.playingNotes[previousNote] {
                        self.midiManager.cancelScheduledEvent(id: scheduledOffId)
                        self.playingNotes.removeValue(forKey: previousNote)
                    }
                    self.midiManager.sendNoteOff(note: previousNote, velocity: 0, channel: 0)
                }

                // Schedule the new note
                self.midiManager.scheduleNoteOn(note: item.note, velocity: velocity, channel: 0, scheduledUptimeMs: scheduledNoteOnUptimeMs)
                self.stringNotes[item.stringIndex] = item.note

                let scheduledNoteOffUptimeMs = scheduledNoteOnUptimeMs + (duration * 1000.0)
                let offId = self.midiManager.scheduleNoteOff(note: item.note, velocity: 0, channel: 0, scheduledUptimeMs: scheduledNoteOffUptimeMs)
                
                self.playingNotes[item.note] = offId
            }
        }
    }

    func panic() {
        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
        playingNotes.removeAll()
        stringNotes.removeAll()
    }
}
