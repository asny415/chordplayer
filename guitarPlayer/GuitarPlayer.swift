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

    func playChord(chordName: String, pattern: [MusicPatternEvent], tempo: Double = 120.0, key: String = "C", capo: Int = 0, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        guard let chordDefinition = appData.chordLibrary?[chordName] else {
            print("[GuitarPlayer] Chord definition for \(chordName) not found.")
            return
        }
        print("[GuitarPlayer] Playing chord: \(chordName) key:\(key) tempo:\(tempo) duration:\(duration)s")

        // Compute transpose offset based on key (C=0, C#=1, ...)
        var transposeOffset = 0
        if let idx = appData.KEY_CYCLE.firstIndex(of: key) {
            transposeOffset = idx
        }

        // Build MIDI notes for each string (muted strings get -1)
        var midiNotes: [Int] = Array(repeating: -1, count: 6)
        for (i, fretVal) in chordDefinition.enumerated() {
            if let fv = fretVal as? StringOrInt {
                switch fv {
                case .int(let fretInt):
                    midiNotes[i] = MusicTheory.standardGuitarTuning[i] + fretInt + transposeOffset + capo
                case .string(_):
                    midiNotes[i] = -1
                }
            } else {
                midiNotes[i] = -1
            }
        }

        print("[GuitarPlayer] Generated MIDI Notes (muted=-1): \(midiNotes)")

        // Stop any currently playing notes from previous chord
        panic()

        // JS uses wholeNoteTime = (60/tempo)*4*1000 ms; we'll compute seconds
        let wholeNoteSeconds = (60.0 / tempo) * 4.0

        // First compute schedule (timestamp in seconds relative to now) following JS semantics
        var schedule: [(timestamp: TimeInterval, notes: [Int])] = []
        var rhythmicTime: TimeInterval = 0
        var physicalTime: TimeInterval = 0

        for event in pattern {
            var delaySeconds: TimeInterval = 0
            switch event.delay {
            case .string(let s):
                if let parsed = MusicTheory.parseDelay(delayString: s) {
                    delaySeconds = parsed * wholeNoteSeconds
                    rhythmicTime += delaySeconds
                    physicalTime = rhythmicTime
                } else if let ms = Double(s) {
                    delaySeconds = ms / 1000.0
                    physicalTime += delaySeconds
                } else {
                    print("[GuitarPlayer] Could not parse delay string: \(s)")
                    continue
                }
            case .double(let d):
                delaySeconds = d / 1000.0
                physicalTime += delaySeconds
            case .int(let i):
                delaySeconds = Double(i) / 1000.0
                physicalTime += delaySeconds
            }

            schedule.append((timestamp: physicalTime, notes: event.notes))
        }

        // Log the computed schedule for diagnosis
        print("[GuitarPlayer] Computed schedule (seconds from now):")
        for (i, item) in schedule.enumerated() {
            print("  [\(i)] t=\(String(format: "%.3f", item.timestamp))s notes=\(item.notes)")
        }

        // Now schedule each event relative to now
        for item in schedule {
            let eventTimestamp = item.timestamp
            for stringNumber in item.notes {
                let actualStringIndex = stringNumber - 1
                guard actualStringIndex >= 0 && actualStringIndex < midiNotes.count else {
                    print("[GuitarPlayer] Invalid string index \(stringNumber) in pattern event for chord \(chordName).")
                    continue
                }
                let noteToPlay = midiNotes[actualStringIndex]
                if noteToPlay == -1 { continue }

                DispatchQueue.main.asyncAfter(deadline: .now() + eventTimestamp) {
                    let nowOffset = Date().timeIntervalSince1970
                    print("[GuitarPlayer] Note ON: \(noteToPlay) vel:\(velocity) scheduledOffset:\(String(format: "%.3f", eventTimestamp)) nowEpoch:\(String(format: "%.3f", nowOffset))")
                    self.midiManager.sendNoteOn(note: UInt8(noteToPlay), velocity: velocity)

                    let noteOffTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                        print("[GuitarPlayer] Note OFF: \(noteToPlay) duration:\(duration)")
                        self?.midiManager.sendNoteOff(note: UInt8(noteToPlay), velocity: 0)
                        self?.playingNotes.removeValue(forKey: UInt8(noteToPlay))
                    }
                    self.playingNotes[UInt8(noteToPlay)] = noteOffTimer
                }
            }
        }
    }

    func panic() {
        print("[GuitarPlayer] panic() called. Sending MIDI panic and clearing \(playingNotes.count) pending notes.")
        if !playingNotes.isEmpty {
            print("[GuitarPlayer] pending notes to clear: \(Array(playingNotes.keys))")
        }
        midiManager.sendPanic()
        // Invalidate all pending note-off timers
        for (note, timer) in playingNotes {
            timer.invalidate()
            print("[GuitarPlayer] Invalidated timer for note \(note)")
        }
        playingNotes.removeAll()
    }
}
