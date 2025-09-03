import Foundation
import Combine

class GuitarPlayer: ObservableObject {
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
            print("[GuitarPlayer] Chord definition for \(chordName) not found.")
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

        let activeChordNotes: [Int] = midiNotes.filter { $0 != -1 }
        
        panic() // Stop previous notes before playing new ones

        let wholeNoteSeconds = (60.0 / tempo) * 4.0
        let schedulingStartUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0

        for event in pattern.pattern {
            guard let delayFraction = MusicTheory.parseDelay(delayString: event.delay) else {
                print("[GuitarPlayer] Could not parse delay string: \(event.delay)")
                continue
            }
            let eventBaseTimeMs = schedulingStartUptimeMs + (delayFraction * wholeNoteSeconds * 1000.0)

            var notesToSchedule: [(note: UInt8, stringIndex: Int)] = []
            for noteValue in event.notes {
                var resolvedNote: (note: Int, stringIndex: Int)?

                switch noteValue {
                case .int(let stringNumber):
                    let stringIndex = stringNumber - 1
                    if stringIndex >= 0 && stringIndex < midiNotes.count && midiNotes[stringIndex] != -1 {
                        resolvedNote = (note: midiNotes[stringIndex], stringIndex: stringIndex)
                    }
                case .string(let symbol):
                    var index = 0
                    if symbol.starts(with: "ROOT") {
                        let numPart = symbol.replacingOccurrences(of: "ROOT", with: "").replacingOccurrences(of: "-", with: "")
                        if numPart.isEmpty { index = 0 }
                        else if let num = Int(numPart) { index = num }
                    }
                    
                    if index >= 0 && index < activeChordNotes.count {
                        let noteToFind = activeChordNotes[index]
                        if let stringIndex = midiNotes.firstIndex(of: noteToFind) {
                            resolvedNote = (note: noteToFind, stringIndex: stringIndex)
                        }
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
