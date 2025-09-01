import Foundation
import Combine

class GuitarPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData // To access chord and pattern libraries

    // Keep track of currently playing notes to send note-off
    private var playingNotes: [UInt8: Timer] = [:]

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.appData = appData
    }

    func playChord(chordName: String, pattern: [MusicPatternEvent], velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        guard let chordDefinition = appData.chordLibrary?[chordName] else {
            print("[GuitarPlayer] Chord definition for \(chordName) not found.")
            return
        }
        print("[GuitarPlayer] Playing chord: \(chordName)")
        let midiNotes = MusicTheory.chordToMidiNotes(chordDefinition: chordDefinition, tuning: MusicTheory.standardGuitarTuning)
        print("Generated MIDI Notes (with muted strings as -1): \(midiNotes)")

        // Stop any currently playing notes from previous chord
        panic()

        var accumulatedDelay: TimeInterval = 0

        for event in pattern {
            // Calculate the actual delay in seconds
            guard let eventDelay = metronome.duration(forNoteValue: event.delay) else {
                print("Could not parse delay for pattern event: \(event.delay)")
                continue
            }

            // Schedule note-on for each note in the event
            for stringIndex in event.notes {
                // Adjust stringIndex to be 0-indexed for array access
                let actualStringIndex = stringIndex - 1
                guard actualStringIndex >= 0 && actualStringIndex < midiNotes.count else {
                    print("Invalid string index \(stringIndex) in pattern event for chord \(chordName).")
                    continue
                }
                let noteToPlay = midiNotes[actualStringIndex]
                if noteToPlay == -1 { continue } // Skip muted strings

                DispatchQueue.main.asyncAfter(deadline: .now() + accumulatedDelay) {
                    print("[GuitarPlayer] Note ON: \(noteToPlay) vel:\(velocity) delay:\(accumulatedDelay)")
                    self.midiManager.sendNoteOn(note: UInt8(noteToPlay), velocity: velocity)

                    // Schedule note-off after the specified duration
                    let noteOffTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                            print("[GuitarPlayer] Note OFF: \(noteToPlay) duration:\(duration)")
                        self?.midiManager.sendNoteOff(note: UInt8(noteToPlay), velocity: 0)
                        self?.playingNotes.removeValue(forKey: UInt8(noteToPlay))
                    }
                    // Store the timer to be able to invalidate it if panic is called
                    self.playingNotes[UInt8(noteToPlay)] = noteOffTimer
                }
            }
            accumulatedDelay += eventDelay
        }
    }

    func panic() {
        midiManager.sendPanic()
        // Invalidate all pending note-off timers
        for (_, timer) in playingNotes {
            timer.invalidate()
        }
        playingNotes.removeAll()
    }
}
