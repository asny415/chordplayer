import Foundation
import Combine

class DrumPlayer: ObservableObject {
    
    private enum PlaybackState {
        case stopped, playing, previewing
    }

    private var midiManager: MidiManager
    private var appData: AppData

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentPreviewStep: Int? = nil
    
    // --- State Management ---
    private var playbackState: PlaybackState = .stopped
    private var uiUpdateTimer: Timer?
    private var measureScheduler: DispatchWorkItem?

    // Timing & Scheduling
    private(set) var startTimeMs: Double = 0
    private var beatDurationMs: Double = 0
    private var beatsPerMeasure: Int = 4
    private var measureDurationMs: Double = 0
    
    // UI Update scheduling
    private var uiUpdateTasks: [DispatchWorkItem] = []

    // Pattern Management
    private var currentPattern: DrumPattern?
    private var nextPattern: DrumPattern?
    private var currentPatternSchedule: [(timestampMs: Double, notes: [Int])]?
    
    private var lastScheduledMeasure: Int = -1
    
    private let countInNote: UInt8 = 42 // Closed Hi-hat

    var clockInfo: (isPlaying: Bool, startTime: Double, loopDuration: Double) {
        return (isPlaying: playbackState != .stopped, startTime: startTimeMs, loopDuration: measureDurationMs)
    }

    func playNote(midiNumber: Int) {
        midiManager.sendNoteOn(note: UInt8(midiNumber), velocity: 100, channel: 9)
        // Automatically send a note-off after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNumber), velocity: 0, channel: 9)
        }
    }

    init(midiManager: MidiManager, appData: AppData) {
        self.midiManager = midiManager
        self.appData = appData
    }

    // MARK: - Preview Player
    // This is the original preview function, kept for compatibility.
    // It has its own scheduling logic and does not interfere with the main player.
    private var previewWorkItem: DispatchWorkItem?
    private var previewLoopDuration: Double = 0
    private var previewStartTime: Double = 0
    private var previewSchedule: [(timestampMs: Double, notes: [Int])]?
    private var previewPatternIndex = 0
    private var previewLoopCount = 0
    
    public func play(drumPattern: DrumPattern, timeSignature: String, bpm: Double) {
        stop() // Stop any player if it's running

        self.playbackState = .previewing
        self.isPlaying = true
        
        let wholeNoteMs = (60.0 / bpm) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }

        self.previewLoopDuration = newLoopDurationMs
        self.previewStartTime = ProcessInfo.processInfo.systemUptime * 1000.0
        self.previewPatternIndex = 0
        self.previewLoopCount = 0
        self.previewSchedule = buildSchedule(from: drumPattern.pattern, wholeNoteMs: wholeNoteMs)

        print("[DrumPlayer] started preview pattern=\(drumPattern.displayName) tempo=\(bpm) timeSignature=\(timeSignature) loopDuration=\(newLoopDurationMs)ms")
        
        if let first = self.previewSchedule?.first {
            let firstEventAbsoluteUptimeMs = previewStartTime + first.timestampMs
            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let firstDelayMs = max(0, firstEventAbsoluteUptimeMs - nowUptimeMs)
            scheduleNextPreviewTick(afterDelayMs: firstDelayMs)
        }
    }
    
    private func scheduleNextPreviewTick(afterDelayMs delayMs: Double) {
        previewWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.previewTick() }
        previewWorkItem = work
        DispatchQueue(label: "com.guitastudio.drumPreviewScheduler", qos: .userInitiated).asyncAfter(deadline: .now() + (delayMs / 1000.0), execute: work)
    }
    
    private func previewTick() {
        guard playbackState == .previewing, let schedule = previewSchedule, !schedule.isEmpty else { return }
        
        let ev = schedule[previewPatternIndex]
        DispatchQueue.main.async { self.currentPreviewStep = self.previewPatternIndex }

        let scheduledOnUptimeMs = previewStartTime + (Double(previewLoopCount) * previewLoopDuration) + ev.timestampMs
        for note in ev.notes {
            midiManager.sendNoteOnScheduled(note: UInt8(note), velocity: 100, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs)
            let scheduledOffUptimeMs = scheduledOnUptimeMs + 200.0
            midiManager.sendNoteOffScheduled(note: UInt8(note), velocity: 0, channel: 9, scheduledUptimeMs: scheduledOffUptimeMs)
        }

        previewPatternIndex += 1
        if previewPatternIndex >= schedule.count {
            previewPatternIndex = 0
            previewLoopCount += 1
        }

        let next = schedule[previewPatternIndex]
        let nextEventAbsoluteUptimeMs = previewStartTime + (Double(previewLoopCount) * previewLoopDuration) + next.timestampMs
        let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        let delayMs = max(0, nextEventAbsoluteUptimeMs - nowUptimeMs)
        scheduleNextPreviewTick(afterDelayMs: delayMs)
    }

    // MARK: - Main Player
    
    func playPattern(tempo: Double = 120.0, velocity: UInt8 = 100, durationMs: Int = 200) {
        let timeSignature = appData.performanceConfig.timeSignature
        guard let patternName = appData.performanceConfig.activeDrumPatternId,
              let drumPattern = findDrumPattern(named: patternName, timeSignature: timeSignature) else {
            print("[DrumPlayer] Could not find pattern '\(appData.performanceConfig.activeDrumPatternId ?? "nil")'.")
            return
        }

        if playbackState == .playing {
            print("[DrumPlayer] Queued pattern: \(patternName)")
            self.nextPattern = drumPattern
            return
        }

        stop(isInternal: true)
        
        // 1. Configure timing
        let timeSigParts = timeSignature.split(separator: "/")
        self.beatsPerMeasure = (timeSigParts.count == 2) ? (Int(timeSigParts[0]) ?? 4) : 4
        self.beatDurationMs = (60.0 / tempo) * 1000.0
        self.measureDurationMs = Double(beatsPerMeasure) * beatDurationMs
        
        // 2. Set master start time. THIS IS THE ONLY PLACE.
        self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        
        // 3. Set state and queue the first pattern
        self.playbackState = .playing
        self.isPlaying = true
        self.nextPattern = drumPattern
        self.lastScheduledMeasure = -1

        // 4. Start the measure scheduler (which will also handle UI updates)
        scheduleMeasureAndReschedule(after: 0)
        
        print("[DrumPlayer] Playback started. Tempo: \(tempo), Time Signature: \(timeSignature)")
    }
    

    private func scheduleMeasureAndReschedule(after delayMs: Double) {
        measureScheduler?.cancel()
        
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.playbackState == .playing else { return }

            let nowMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let elapsedMs = nowMs - self.startTimeMs
            
            let currentMeasure = Int(floor(elapsedMs / self.measureDurationMs))
            
            if currentMeasure > self.lastScheduledMeasure {
                self.lastScheduledMeasure = currentMeasure
                
                // --- UI Update Logic (synchronized with MIDI events) ---
                self.scheduleUIUpdatesForMeasure(currentMeasure)
                
                // --- Pattern Switching Logic ---
                let isFirstFormalMeasure = (currentMeasure == 1)
                let isNewMeasureAfterFirst = (currentMeasure > 1)
                
                if (isFirstFormalMeasure || isNewMeasureAfterFirst), let patternToSwitch = self.nextPattern {
                    self.currentPattern = patternToSwitch
                    self.nextPattern = nil
                    let wholeNoteMs = self.beatDurationMs * 4.0
                    self.currentPatternSchedule = self.buildSchedule(from: self.currentPattern!.pattern, wholeNoteMs: wholeNoteMs)
                    print("[DrumPlayer] \(isFirstFormalMeasure ? "Starting with" : "Switched to") pattern: \(self.currentPattern!.displayName)")
                }
                
                // --- Sound Scheduling Logic ---
                let measureStartUptimeMs = self.startTimeMs + (Double(currentMeasure) * self.measureDurationMs)

                if currentMeasure == 0 { // Count-in measure
                    for i in 0..<self.beatsPerMeasure {
                        let beatUptimeMs = self.startTimeMs + (Double(i) * self.beatDurationMs)
                        self.midiManager.sendNoteOnScheduled(note: self.countInNote, velocity: 100, channel: 9, scheduledUptimeMs: beatUptimeMs)
                        self.midiManager.sendNoteOffScheduled(note: self.countInNote, velocity: 0, channel: 9, scheduledUptimeMs: beatUptimeMs + 100)
                    }
                } else if let schedule = self.currentPatternSchedule { // Formal pattern measures
                    for event in schedule {
                        let scheduledOnUptimeMs = measureStartUptimeMs + event.timestampMs
                        for note in event.notes {
                            self.midiManager.sendNoteOnScheduled(note: UInt8(note), velocity: 100, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs)
                            self.midiManager.sendNoteOffScheduled(note: UInt8(note), velocity: 0, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs + 200)
                        }
                    }
                }
            }
            
            // --- Check if auto-play is complete ---
            if (self.appData.playingMode == .automatic || self.appData.playingMode == .assisted) && !self.appData.autoPlaySchedule.isEmpty {
                let totalBeatsInSchedule = self.appData.autoPlaySchedule.reduce(0) { result, event in
                    return max(result, event.triggerBeat + (event.durationBeats ?? 0))
                }
                
                // Calculate which measure contains the last event
                let lastMeasureWithContent = Int(ceil(Double(totalBeatsInSchedule) / Double(self.beatsPerMeasure)))
                
                // Stop after the last measure is completely finished
                if currentMeasure > lastMeasureWithContent {
                    print("[DrumPlayer] Auto-play complete (last measure finished), stopping...")
                    DispatchQueue.main.async {
                        self.stop()
                    }
                    return
                }
            }
            
            // --- Reschedule for the next measure ---
            let nextMeasureIndex = currentMeasure + 1
            let nextMeasureStartUptimeMs = self.startTimeMs + (Double(nextMeasureIndex) * self.measureDurationMs)
            let delayUntilNextMeasureMs = max(0, nextMeasureStartUptimeMs - nowMs)
            self.scheduleMeasureAndReschedule(after: delayUntilNextMeasureMs)
        }
        
        measureScheduler = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delayMs / 1000.0, execute: work)
    }

    public func stop(isInternal: Bool = false) {
        if playbackState == .stopped && isInternal { return }
        
        print("[DrumPlayer] stopped")
        
        self.playbackState = .stopped
        self.isPlaying = false
        
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
        measureScheduler?.cancel()
        measureScheduler = nil
        previewWorkItem?.cancel()
        previewWorkItem = nil
        
        // Cancel all scheduled UI update tasks
        for task in uiUpdateTasks {
            task.cancel()
        }
        uiUpdateTasks.removeAll()

        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
        
        self.startTimeMs = 0
        self.currentPattern = nil
        self.nextPattern = nil
        
        let timeSigParts = appData.performanceConfig.timeSignature.split(separator: "/")
        let beatsPerMeasure = (timeSigParts.count == 2) ? (Int(timeSigParts[0]) ?? 4) : 4
        
        DispatchQueue.main.async {
            self.appData.currentMeasure = 0
            self.appData.currentBeat = -beatsPerMeasure
            self.appData.currentlyPlayingChordName = nil
            self.appData.currentlyPlayingPatternName = nil
            self.appData.autoPlaySchedule = []
            self.currentPreviewStep = nil
        }
    }
    
    // MARK: - Helpers
    
    private func findDrumPattern(named name: String, timeSignature: String) -> DrumPattern? {
        if let pattern = appData.drumPatternLibrary?[timeSignature]?[name] {
            return pattern
        } else if let pattern = CustomDrumPatternManager.shared.customDrumPatterns[timeSignature]?[name] {
            return pattern
        }
        return nil
    }
    
    private func buildSchedule(from pattern: [DrumPatternEvent], wholeNoteMs: Double) -> [(timestampMs: Double, notes: [Int])] {
        var rhythmicTime: Double = 0
        var physicalTime: Double = 0
        var newPatternSchedule: [(timestampMs: Double, notes: [Int])] = []

        for event in pattern {
            var delayMs: Double = 0
            if let parsedFraction = MusicTheory.parseDelay(delayString: event.delay) {
                // This is relative to whole note, but our measure duration might be different.
                // Let's assume the pattern is defined for a 4/4 measure.
                let delayRelativeToMeasure = parsedFraction * (wholeNoteMs / measureDurationMs) * measureDurationMs
                rhythmicTime += delayRelativeToMeasure
                physicalTime = rhythmicTime
            } else if let ms = Double(event.delay) {
                delayMs = ms
                physicalTime += delayMs
            } else { continue }
            
            // The schedule timestamp should be relative to the start of the measure.
            newPatternSchedule.append((timestampMs: physicalTime.truncatingRemainder(dividingBy: measureDurationMs), notes: event.notes))
        }
        return newPatternSchedule.sorted(by: { $0.timestampMs < $1.timestampMs })
    }
    
    // MARK: - UI Update Logic
    
    private func scheduleUIUpdatesForMeasure(_ measureIndex: Int) {
        // Calculate UI state for this measure and schedule beat-by-beat updates
        let measureStartUptimeMs = startTimeMs + (Double(measureIndex) * measureDurationMs)
        
        for beat in 0..<beatsPerMeasure {
            let beatUptimeMs = measureStartUptimeMs + (Double(beat) * beatDurationMs)
            let nowMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let delayMs = max(0, beatUptimeMs - nowMs)
            
            // Create a cancellable UI update task
            let task = DispatchWorkItem { [weak self] in
                guard let self = self, self.playbackState == .playing else { return }
                
                let newMeasure: Int
                let newBeat: Int
                
                if measureIndex == 0 {
                    // Count-in phase
                    newMeasure = 0
                    newBeat = beat - self.beatsPerMeasure
                } else {
                    // Normal playback
                    newMeasure = measureIndex
                    newBeat = beat
                }
                
                // Only update if the values actually changed to avoid unnecessary UI updates
                if self.appData.currentMeasure != newMeasure {
                    self.appData.currentMeasure = newMeasure
                }
                if self.appData.currentBeat != newBeat {
                    self.appData.currentBeat = newBeat
                }
            }
            
            // Store the task so we can cancel it later if needed
            uiUpdateTasks.append(task)
            
            // Schedule the task
            DispatchQueue.main.asyncAfter(deadline: .now() + (delayMs / 1000.0), execute: task)
        }
    }
}


