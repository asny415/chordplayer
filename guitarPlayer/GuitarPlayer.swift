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

                        // compute scheduled uptime (ms)
                        let schedulingStartUptimeMs = schedulingStartUptime * 1000.0
                        let scheduledNoteOnUptimeMs = schedulingStartUptimeMs + (eventTimestamp * 1000.0)
                        schedulingQueue.async { [weak self] in
                            Thread.current.threadPriority = 1.0
                            guard let self = self else { return }
                            // Send note on scheduled via MidiManager
                            // Before playing, if this string had a previous sounding note, cancel its off and send noteOff
                            if let prev = self.stringNotes[actualStringIndex], prev >= 0 {
                                let prevNote = UInt8(prev)
                                if let prevWork = self.playingNotes[prevNote] {
                                    prevWork.cancel()
                                    self.playingNotes.removeValue(forKey: prevNote)
                                }
                                // send previous note off immediately (scheduled nil -> immediate)
                                self.midiManager.sendNoteOffScheduled(note: prevNote, velocity: 0, scheduledUptimeMs: nil)
                            }

                            // Send note on with timestamp and keep token for potential cancellation
                            let onToken = self.midiManager.scheduleNoteOn(note: UInt8(noteToPlay), velocity: velocity, channel: 0, scheduledUptimeMs: scheduledNoteOnUptimeMs)
                            // Schedule note off using MidiManager time-stamped send and store token
                            let scheduledNoteOffUptimeMs = scheduledNoteOnUptimeMs + (duration * 1000.0)
                            let offToken = self.midiManager.scheduleNoteOff(note: UInt8(noteToPlay), velocity: 0, channel: 0, scheduledUptimeMs: scheduledNoteOffUptimeMs)
                            // Store offToken in playingNotes so we can cancel it if note is preempted
                            // reuse UInt8(note) as key
                            // store token's UUID via mapping from note->UUID string via Data conversion
                            // For simplicity, wrap UUID in Data by using its uuidString -> store hashValue as Int
                            self.playingNotes[UInt8(noteToPlay)] = DispatchWorkItem { [weak self] in
                                if let id = onToken as UUID? { self?.midiManager.cancelScheduledEvent(id: id) }
                                if let id = offToken as UUID? { self?.midiManager.cancelScheduledEvent(id: id) }
                            }
                }
            }
        }
    }

    func panic() {
    // minimize logging in panic to reduce overhead
        midiManager.sendPanic()
        // Cancel all pending note-off work items
        // Cancel any scheduled events via MidiManager
        for (note, work) in playingNotes {
            work.cancel()
        }
        playingNotes.removeAll()
        // Also cancel any pending scheduled events in the MidiManager
        midiManager.cancelAllPendingScheduledEvents()
    }
}
