import Foundation
import Combine

class DrumPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData // To access drum pattern library

    private var currentPatternTimer: Timer?
    private var currentPatternEvents: [DrumPatternEvent]?
    private var currentPatternIndex: Int = 0
    // Work item for the next scheduled tick so we can cancel it on stop()
    private var scheduledWorkItem: DispatchWorkItem?
        // Clock info for quantization
            @Published private(set) var isPlaying: Bool = false
            private(set) var startTimeMs: Double = 0
            private(set) var loopDurationMs: Double = 0

        var clockInfo: (isPlaying: Bool, startTime: Double, loopDuration: Double) {
            return (isPlaying: isPlaying, startTime: startTimeMs, loopDuration: loopDurationMs)
        }

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.appData = appData
    }

    func playPattern(patternName: String, tempo: Double = 120.0, timeSignature: String = "4/4", velocity: UInt8 = 100, durationMs: Int = 200) {
        stop() // Stop any existing pattern

        guard let pattern = appData.drumPatternLibrary?[patternName] else {
            print("[DrumPlayer] Pattern definition for \(patternName) not found.")
            return
        }

        // Build schedule similar to JS: wholeNoteTime in ms, rhythmic vs physical time
        let wholeNoteMs = (60.0 / tempo) * 4.0 * 1000.0
        var rhythmicTime: Double = 0
        var physicalTime: Double = 0
        var schedule: [(timestampMs: Double, notes: [Int])] = []

        for event in pattern {
            // reuse JS-like _getDelayInMs semantics via metronome parsing
            var delayMs: Double = 0
            // event.delay in DrumPatternEvent is String
            if let parsedFraction = MusicTheory.parseDelay(delayString: event.delay) {
                delayMs = parsedFraction * wholeNoteMs
                rhythmicTime += delayMs
                physicalTime = rhythmicTime
            } else if let ms = Double(event.delay) {
                delayMs = ms
                physicalTime += delayMs
            } else {
                print("[DrumPlayer] Could not parse delay for drum event: \(event.delay)")
                continue
            }
            schedule.append((timestampMs: physicalTime, notes: event.notes))
        }

        // compute loopDuration from timeSignature
        var loopDurationMs: Double = wholeNoteMs
        do {
            let parts = timeSignature.split(separator: "/").map { String($0) }
            if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
                loopDurationMs = (beats / beatType) * wholeNoteMs
            } else {
                loopDurationMs = wholeNoteMs
            }
        }

        // store schedule and timing
        self.currentPatternEvents = pattern
        self.currentPatternIndex = 0

        // Save computed schedule and start looping
        // Use monotonic uptime (ms) as baseline to avoid mixing wall-clock vs uptime
        let startUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
    // update clock info for quantization (set synchronously)
    self.isPlaying = true
    print("[DrumPlayer] started pattern=\(patternName) tempo=\(tempo) timeSignature=\(timeSignature) loopDuration=\(loopDurationMs)ms")
        self.startTimeMs = startUptimeMs
        self.loopDurationMs = loopDurationMs
        var scheduleIndex = 0
        var loopCount = 0

        // local copy of schedule and durations
        let scheduleCopy = schedule
        let noteDurationSeconds = Double(durationMs) / 1000.0

    // minimal logging: remove detailed schedule prints to reduce runtime overhead

        // schedule function using background queue and monotonic uptime
        let schedulingQueue = DispatchQueue(label: "com.guitastudio.drumScheduler", qos: .userInitiated)

        func scheduleNextTick(afterDelayMs delayMs: Double) {
            // cancel any previously scheduled work item
            scheduledWorkItem?.cancel()
            let work = DispatchWorkItem { tick() }
            scheduledWorkItem = work
            schedulingQueue.asyncAfter(deadline: .now() + (delayMs / 1000.0), execute: work)
        }

        func tick() {
            // stop if flag cleared
            if !self.isPlaying { return }
            guard !scheduleCopy.isEmpty else { return }
            let ev = scheduleCopy[scheduleIndex]
            // boost thread priority for timing-critical work
            Thread.current.threadPriority = 1.0
            // compute scheduled uptime for this event in ms
            let scheduledOnUptimeMs = startUptimeMs + (Double(loopCount) * loopDurationMs) + ev.timestampMs
            for note in ev.notes {
                midiManager.sendNoteOnScheduled(note: UInt8(note), velocity: velocity, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs)
                // schedule note off at scheduledOnUptimeMs + durationMs
                let scheduledOffUptimeMs = scheduledOnUptimeMs + (Double(durationMs))
                midiManager.sendNoteOffScheduled(note: UInt8(note), velocity: 0, channel: 9, scheduledUptimeMs: scheduledOffUptimeMs)
            }

            scheduleIndex += 1
            if scheduleIndex >= scheduleCopy.count {
                scheduleIndex = 0
                loopCount += 1
            }

            // compute next event absolute uptime
            let next = scheduleCopy[scheduleIndex]
            let nextEventAbsoluteUptimeMs = startUptimeMs + (Double(loopCount) * loopDurationMs) + next.timestampMs
            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let delayMs = max(0, nextEventAbsoluteUptimeMs - nowUptimeMs)

            // schedule next tick
            scheduleNextTick(afterDelayMs: delayMs)
        }

        // schedule first tick
        if let first = schedule.first {
            let firstEventAbsoluteUptimeMs = startUptimeMs + first.timestampMs
            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let firstDelayMs = max(0, firstEventAbsoluteUptimeMs - nowUptimeMs)
            scheduleNextTick(afterDelayMs: firstDelayMs)
        }
    }

    func stop() {
    // Prevent further scheduled ticks from running
    self.isPlaying = false
    print("[DrumPlayer] stopped")
    // Cancel any scheduled work item
    scheduledWorkItem?.cancel()
    scheduledWorkItem = nil

    currentPatternTimer?.invalidate()
    currentPatternTimer = nil
    currentPatternEvents = nil
    currentPatternIndex = 0
    // reset clock info
    self.startTimeMs = 0
    self.loopDurationMs = 0
    midiManager.sendPanic() // Send panic to ensure all drum notes are off
    midiManager.cancelAllPendingScheduledEvents()
    }
}
