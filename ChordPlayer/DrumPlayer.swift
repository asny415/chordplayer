import Foundation
import Combine

class DrumPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData

    @Published private(set) var currentStep: Int? = nil

    private var currentPatternTimer: Timer?
    private var currentPatternEvents: [DrumPatternEvent]?
    private var currentPatternIndex: Int = 0
    private var loopCount: Int = 0
    private var currentVelocity: UInt8 = 100
    private var currentDurationMs: Int = 200
    private var scheduledWorkItem: DispatchWorkItem?

    private var beatTimer: Timer?
    private var beatsPerMeasure: Int = 4
    private var beatCounter: Int = 0
    private var measureCounter: Int = 0

    @Published private(set) var isPlaying: Bool = false
    private(set) var startTimeMs: Double = 0
    private(set) var loopDurationMs: Double = 0

    private var queuedPatternName: String?
    private var queuedPatternEvents: [DrumPatternEvent]?
    private var queuedLoopDurationMs: Double?
    private var queuedPatternSchedule: [(timestampMs: Double, notes: [Int])]?
    private var currentPatternSchedule: [(timestampMs: Double, notes: [Int])]?

    var clockInfo: (isPlaying: Bool, startTime: Double, loopDuration: Double) {
        return (isPlaying: isPlaying, startTime: startTimeMs, loopDuration: loopDurationMs)
    }

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.appData = appData
        self.loopCount = 0
    }

    // Plays a single MIDI note immediately.
    public func playNote(midiNumber: Int) {
        midiManager.sendNoteOn(note: UInt8(midiNumber), velocity: 120, channel: 9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNumber), velocity: 0, channel: 9)
        }
    }

    // Plays a specific drum pattern, typically for preview purposes.
    public func play(drumPattern: DrumPattern, timeSignature: String, bpm: Double) {
        stop() // Stop any existing playback first.

        let wholeNoteMs = (60.0 / bpm) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }

        var rhythmicTime: Double = 0
        var physicalTime: Double = 0
        var newPatternSchedule: [(timestampMs: Double, notes: [Int])] = []

        for event in drumPattern.pattern {
            var delayMs: Double = 0
            if let parsedFraction = MusicTheory.parseDelay(delayString: event.delay) {
                delayMs = parsedFraction * wholeNoteMs
                rhythmicTime += delayMs
                physicalTime = rhythmicTime
            } else if let ms = Double(event.delay) {
                delayMs = ms
                physicalTime += delayMs
            } else {
                continue
            }
            newPatternSchedule.append((timestampMs: physicalTime, notes: event.notes))
        }

        self.currentPatternEvents = drumPattern.pattern
        self.loopDurationMs = newLoopDurationMs
        self.isPlaying = true
        self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        self.currentPatternIndex = 0
        self.loopCount = 0
        self.currentPatternSchedule = newPatternSchedule

        print("[DrumPlayer] started preview pattern=\(drumPattern.displayName) tempo=\(bpm) timeSignature=\(timeSignature) loopDuration=\(newLoopDurationMs)ms")

        if let first = self.currentPatternSchedule?.first {
            let firstEventAbsoluteUptimeMs = startTimeMs + first.timestampMs
            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let firstDelayMs = max(0, firstEventAbsoluteUptimeMs - nowUptimeMs)
            scheduleNextTick(afterDelayMs: firstDelayMs)
        }
    }

    func playPattern(tempo: Double = 120.0, velocity: UInt8 = 100, durationMs: Int = 200) {
        let timeSignature = appData.performanceConfig.timeSignature
        guard let patternName = appData.performanceConfig.activeDrumPatternId else {
            print("[DrumPlayer] No active drum pattern selected in appData.")
            return
        }
        var drumPattern: DrumPattern?
        if let pattern = appData.drumPatternLibrary?[timeSignature]?[patternName] {
            drumPattern = pattern
        } else if let pattern = CustomDrumPatternManager.shared.customDrumPatterns[timeSignature]?[patternName] {
            drumPattern = pattern
        }

        guard let drumPattern = drumPattern else {
            print("[DrumPlayer] Pattern definition for \(patternName) in time signature \(timeSignature) not found in preset or custom libraries.")
            return
        }

        let wholeNoteMs = (60.0 / tempo) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }

        var rhythmicTime: Double = 0
        var physicalTime: Double = 0
        var newPatternSchedule: [(timestampMs: Double, notes: [Int])] = []

        for event in drumPattern.pattern {
            var delayMs: Double = 0
            if let parsedFraction = MusicTheory.parseDelay(delayString: event.delay) {
                delayMs = parsedFraction * wholeNoteMs
                rhythmicTime += delayMs
                physicalTime = rhythmicTime
            } else if let ms = Double(event.delay) {
                delayMs = ms
                physicalTime += delayMs
            } else {
                continue
            }
            newPatternSchedule.append((timestampMs: physicalTime, notes: event.notes))
        }

        if isPlaying {
            self.queuedPatternName = patternName
            self.queuedPatternEvents = drumPattern.pattern
            self.queuedLoopDurationMs = newLoopDurationMs
            self.queuedPatternSchedule = newPatternSchedule
            print("[DrumPlayer] Queued pattern: \(patternName)")
        } else {
            stop()
            self.currentPatternEvents = drumPattern.pattern
            self.loopDurationMs = newLoopDurationMs
            self.isPlaying = true
            self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            self.currentPatternIndex = 0
            self.loopCount = 0
            self.currentPatternSchedule = newPatternSchedule

            // Reset and start beat counter
            self.beatTimer?.invalidate()
            let timeSigParts = timeSignature.split(separator: "/")
            if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
                self.beatsPerMeasure = beats
            } else {
                self.beatsPerMeasure = 4
            }
            self.measureCounter = 1
            self.beatCounter = 1
            let beatDuration = 60.0 / tempo
            
            DispatchQueue.main.async {
                self.appData.currentMeasure = self.measureCounter
                self.appData.currentBeat = self.beatCounter
            }

            self.beatTimer = Timer.scheduledTimer(withTimeInterval: beatDuration, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }

                self.beatCounter += 1
                if self.beatCounter > self.beatsPerMeasure {
                    self.beatCounter = 1
                    self.measureCounter += 1
                }
                
                DispatchQueue.main.async {
                    self.appData.currentMeasure = self.measureCounter
                    self.appData.currentBeat = self.beatCounter
                }
            }

            print("[DrumPlayer] started pattern=\(patternName) tempo=\(tempo) timeSignature=\(timeSignature) loopDuration=\(newLoopDurationMs)ms")

            if let first = self.currentPatternSchedule?.first {
                let firstEventAbsoluteUptimeMs = startTimeMs + first.timestampMs
                let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
                let firstDelayMs = max(0, firstEventAbsoluteUptimeMs - nowUptimeMs)
                scheduleNextTick(afterDelayMs: firstDelayMs)
            }
        }
    }

    private func scheduleNextTick(afterDelayMs delayMs: Double) {
        scheduledWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.tick()
        }
        scheduledWorkItem = work
        DispatchQueue(label: "com.guitastudio.drumScheduler", qos: .userInitiated).asyncAfter(deadline: .now() + (delayMs / 1000.0), execute: work)
    }

    private func tick() {
        if !self.isPlaying { return }

        if currentPatternIndex == 0 && queuedPatternName != nil {
            print("[DrumPlayer] Seamlessly transitioning to queued pattern: \(queuedPatternName!)")
            self.currentPatternEvents = queuedPatternEvents
            self.currentPatternSchedule = queuedPatternSchedule
            self.loopDurationMs = queuedLoopDurationMs ?? self.loopDurationMs

            self.queuedPatternName = nil
            self.queuedPatternEvents = nil
            self.queuedLoopDurationMs = nil
            self.queuedPatternSchedule = nil
        }

        guard let currentSchedule = self.currentPatternSchedule, !currentSchedule.isEmpty else { return }
        let ev = currentSchedule[currentPatternIndex]

        Thread.current.threadPriority = 1.0
        let scheduledOnUptimeMs = startTimeMs + (Double(loopCount) * loopDurationMs) + ev.timestampMs
        for note in ev.notes {
            midiManager.sendNoteOnScheduled(note: UInt8(note), velocity: self.currentVelocity, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs)
            let scheduledOffUptimeMs = scheduledOnUptimeMs + (Double(self.currentDurationMs))
            midiManager.sendNoteOffScheduled(note: UInt8(note), velocity: 0, channel: 9, scheduledUptimeMs: scheduledOffUptimeMs)
        }

        currentPatternIndex += 1
        if currentPatternIndex >= currentSchedule.count {
            currentPatternIndex = 0
            loopCount += 1
        }

        let next = currentSchedule[currentPatternIndex]
        let nextEventAbsoluteUptimeMs = startTimeMs + (Double(loopCount) * loopDurationMs) + next.timestampMs
        let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        let delayMs = max(0, nextEventAbsoluteUptimeMs - nowUptimeMs)

        scheduleNextTick(afterDelayMs: delayMs)
    }

    public func stop() {
        self.isPlaying = false
        print("[DrumPlayer] stopped")
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil

        beatTimer?.invalidate()
        beatTimer = nil
        DispatchQueue.main.async {
            self.appData.currentMeasure = 0
            self.appData.currentBeat = 0
            self.appData.currentlyPlayingChordName = nil
            self.appData.currentlyPlayingPatternName = nil
        }

        currentPatternTimer?.invalidate()
        currentPatternTimer = nil
        currentPatternEvents = nil
        currentPatternIndex = 0
        loopCount = 0
        self.startTimeMs = 0
        self.loopDurationMs = 0
        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
    }
}