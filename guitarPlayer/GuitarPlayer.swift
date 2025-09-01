import Foundation
import Combine

class GuitarPlayer: ObservableObject {
    // Enable timing diagnostics
    // Shared scheduling queue to avoid creating many global queue tasks
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData // To access chord and pattern libraries

    // Keep track of currently playing notes to send note-off (use DispatchWorkItem for cancellable off tasks)
    private var playingNotes: [UInt8: DispatchWorkItem] = [:]
    // Track which MIDI note is sounding for each string (nil if muted)
    private var stringNotes: [Int?] = Array(repeating: nil, count: 6)

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
    // minimal logging: do not print per-play to avoid runtime overhead

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

    // Now schedule each event relative to now using dedicated schedulingQueue
    let schedulingStartUptime = ProcessInfo.processInfo.systemUptime
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

                schedulingQueue.asyncAfter(deadline: .now() + eventTimestamp) { [weak self] in
                    // boost thread priority for MIDI timing work
                    Thread.current.threadPriority = 1.0
                    guard let self = self else { return }
                    // Send note on
                    // Before playing, if this string had a previous sounding note, cancel its off and send noteOff
                    if let prev = self.stringNotes[actualStringIndex], prev >= 0 {
                        let prevNote = UInt8(prev)
                        if let prevWork = self.playingNotes[prevNote] {
                            prevWork.cancel()
                            self.playingNotes.removeValue(forKey: prevNote)
                        }
                        self.midiManager.sendNoteOff(note: prevNote, velocity: 0)
                    }

                    // Send note on
                    // no per-note debug prints to reduce runtime overhead
                    self.midiManager.sendNoteOn(note: UInt8(noteToPlay), velocity: velocity)
                    // record that this string now holds this note
                    self.stringNotes[actualStringIndex] = noteToPlay

                    // Schedule note off using a cancellable DispatchWorkItem to avoid main-thread timers
                    let work = DispatchWorkItem { [weak self] in
                        guard let s = self else { return }
                        s.midiManager.sendNoteOff(note: UInt8(noteToPlay), velocity: 0)
                        s.playingNotes.removeValue(forKey: UInt8(noteToPlay))
                        // Clear stringNotes if it still points to this note
                        if s.stringNotes[actualStringIndex] == noteToPlay {
                            s.stringNotes[actualStringIndex] = nil
                        }
                    }
                    // Store the work item so it can be cancelled by panic()
                    self.playingNotes[UInt8(noteToPlay)] = work
                    self.schedulingQueue.asyncAfter(deadline: .now() + duration, execute: work)
                }
            }
        }
    }

    func panic() {
    // minimize logging in panic to reduce overhead
        midiManager.sendPanic()
        // Cancel all pending note-off work items
        for (note, work) in playingNotes {
            work.cancel()
        }
        playingNotes.removeAll()
    }
}
