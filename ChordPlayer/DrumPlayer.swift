import Foundation
import Combine

class DrumPlayer: ObservableObject {
    
    private enum PlaybackState {
        case stopped, countIn, playing
    }

    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentPreviewStep: Int? = nil
    
    private var playbackState: PlaybackState = .stopped
    private let countInBeats = 4
    private var currentCountInBeat = 0

    private var beatTimer: Timer?
    private var beatsPerMeasure: Int = 4
    private var beatCounter: Int = 0
    private var measureCounter: Int = 0
    
    private(set) var startTimeMs: Double = 0
    private(set) var loopDurationMs: Double = 0

    private var currentPatternEvents: [DrumPatternEvent]?
    private var currentPatternSchedule: [(timestampMs: Double, notes: [Int])]?
    private var currentPatternIndex: Int = 0
    private var loopCount: Int = 0
    
    private var queuedPatternName: String?
    private var queuedPatternEvents: [DrumPatternEvent]?
    private var queuedLoopDurationMs: Double?
    private var queuedPatternSchedule: [(timestampMs: Double, notes: [Int])]?
    
    private var scheduledWorkItem: DispatchWorkItem?
    private let countInNote: UInt8 = 42 // Closed Hi-hat

    var clockInfo: (isPlaying: Bool, startTime: Double, loopDuration: Double) {
        return (isPlaying: playbackState != .stopped, startTime: startTimeMs, loopDuration: loopDurationMs)
    }

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.appData = appData
    }

    public func playNote(midiNumber: Int) {
        midiManager.sendNoteOn(note: UInt8(midiNumber), velocity: 120, channel: 9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNumber), velocity: 0, channel: 9)
        }
    }

    public func play(drumPattern: DrumPattern, timeSignature: String, bpm: Double) {
        stop()

        let wholeNoteMs = (60.0 / bpm) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }

        self.currentPatternEvents = drumPattern.pattern
        self.loopDurationMs = newLoopDurationMs
        self.playbackState = .playing // Preview playback is immediate
        self.isPlaying = true
        self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        self.currentPatternIndex = 0
        self.loopCount = 0
        self.currentPatternSchedule = buildSchedule(from: drumPattern.pattern, wholeNoteMs: wholeNoteMs)

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
        let wholeNoteMs = (60.0 / tempo) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }
        
        if playbackState != .stopped {
            guard let patternName = appData.performanceConfig.activeDrumPatternId,
                  let drumPattern = findDrumPattern(named: patternName, timeSignature: timeSignature) else {
                print("[DrumPlayer] Could not queue pattern, definition not found.")
                return
            }
            
            self.queuedPatternName = patternName
            self.queuedPatternEvents = drumPattern.pattern
            self.queuedLoopDurationMs = newLoopDurationMs
            self.queuedPatternSchedule = buildSchedule(from: drumPattern.pattern, wholeNoteMs: wholeNoteMs)
            print("[DrumPlayer] Queued pattern: \(patternName)")
            return
        }

        stop()
        
        self.playbackState = .countIn
        self.isPlaying = true
        self.currentCountInBeat = countInBeats + 1 // +1 because the first tick will decrement it
        
        if parts.count == 2, let beats = Int(parts[0]) {
            self.beatsPerMeasure = beats
        } else {
            self.beatsPerMeasure = 4
        }
        
        self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        self.loopDurationMs = newLoopDurationMs
        
        buildAutoPlaySchedule()

        let beatDuration = 60.0 / tempo
        
        beatTick(tempo: tempo)
        
        self.beatTimer = Timer.scheduledTimer(withTimeInterval: beatDuration, repeats: true) { [weak self] _ in
            self?.beatTick(tempo: tempo)
        }
    }
    
    private func beatTick(tempo: Double) {
        guard playbackState != .stopped else { return }

        switch playbackState {
        case .countIn:
            midiManager.sendNoteOn(note: countInNote, velocity: 100, channel: 9)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.midiManager.sendNoteOff(note: self.countInNote, velocity: 0, channel: 9)
            }

            DispatchQueue.main.async {
                self.appData.currentMeasure = 0
                self.appData.currentBeat = -self.currentCountInBeat
            }
            
            currentCountInBeat -= 1

            if currentCountInBeat < 0 {
                playbackState = .playing
                measureCounter = 1
                beatCounter = 0
                self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
                startMainPattern(tempo: tempo)
                fallthrough
            }

        case .playing:
            if beatCounter == 0 { // First beat after count-in
                 // Already handled by fallthrough
            } else if !(measureCounter == 1 && beatCounter == 1) { // Subsequent beats
                // This logic seems complex, let's simplify.
            }
            
            beatCounter += 1
            if beatCounter > beatsPerMeasure {
                beatCounter = 1
                measureCounter += 1
            }
            
            DispatchQueue.main.async {
                self.appData.currentMeasure = self.measureCounter
                self.appData.currentBeat = self.beatCounter
            }
            
        case .stopped:
            break
        }
    }
    
    private func startMainPattern(tempo: Double) {
        let timeSignature = appData.performanceConfig.timeSignature
        guard let patternName = appData.performanceConfig.activeDrumPatternId,
              let drumPattern = findDrumPattern(named: patternName, timeSignature: timeSignature) else {
            print("[DrumPlayer] Could not start main pattern, definition not found.")
            stop()
            return
        }

        let wholeNoteMs = (60.0 / tempo) * 4.0 * 1000.0
        var newLoopDurationMs: Double = wholeNoteMs
        let parts = timeSignature.split(separator: "/").map { String($0) }
        if parts.count == 2, let beats = Double(parts[0]), let beatType = Double(parts[1]), beatType != 0 {
            newLoopDurationMs = (beats / beatType) * wholeNoteMs
        }

        self.currentPatternEvents = drumPattern.pattern
        self.loopDurationMs = newLoopDurationMs
        self.currentPatternIndex = 0
        self.loopCount = 0
        self.currentPatternSchedule = buildSchedule(from: drumPattern.pattern, wholeNoteMs: wholeNoteMs)

        print("[DrumPlayer] started pattern=\(patternName) tempo=\(tempo) timeSignature=\(timeSignature) loopDuration=\(newLoopDurationMs)ms")

        if let first = self.currentPatternSchedule?.first {
            let firstEventAbsoluteUptimeMs = startTimeMs + first.timestampMs
            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
            let firstDelayMs = max(0, firstEventAbsoluteUptimeMs - nowUptimeMs)
            scheduleNextTick(afterDelayMs: firstDelayMs)
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
        if playbackState != .playing { return }

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

        DispatchQueue.main.async {
            self.currentPreviewStep = self.currentPatternIndex
        }

        Thread.current.threadPriority = 1.0
        let scheduledOnUptimeMs = startTimeMs + (Double(loopCount) * loopDurationMs) + ev.timestampMs
        for note in ev.notes {
            midiManager.sendNoteOnScheduled(note: UInt8(note), velocity: 100, channel: 9, scheduledUptimeMs: scheduledOnUptimeMs)
            let scheduledOffUptimeMs = scheduledOnUptimeMs + 200.0
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
        self.playbackState = .stopped
        self.isPlaying = false
        print("[DrumPlayer] stopped")
        
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil

        beatTimer?.invalidate()
        beatTimer = nil
        
        DispatchQueue.main.async {
            self.appData.currentMeasure = 0
            self.appData.currentBeat = -self.countInBeats
            self.appData.currentlyPlayingChordName = nil
            self.appData.currentlyPlayingPatternName = nil
            self.appData.autoPlaySchedule = []
            self.currentPreviewStep = nil
        }

        currentPatternEvents = nil
        currentPatternIndex = 0
        loopCount = 0
        self.startTimeMs = 0
        self.loopDurationMs = 0
        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
    }
    
    private func buildAutoPlaySchedule() {
        guard appData.playingMode == .automatic else {
            if !appData.autoPlaySchedule.isEmpty {
                DispatchQueue.main.async { self.appData.autoPlaySchedule = [] }
            }
            return
        }

        var schedule: [AutoPlayEvent] = []
        let timeSignature = appData.performanceConfig.timeSignature
        var beatsPerMeasure = 4
        let timeSigParts = timeSignature.split(separator: "/")
        if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
            beatsPerMeasure = beats
        }

        for chordConfig in appData.performanceConfig.chords {
            for (_, association) in chordConfig.patternAssociations {
                if let measureIndices = association.measureIndices, !measureIndices.isEmpty {
                    for measureIndex in measureIndices {
                        let targetBeat = (measureIndex - 1) * Double(beatsPerMeasure) 
                        let action = AutoPlayEvent(chordName: chordConfig.name, patternId: association.patternId, triggerBeat: Int(round(targetBeat)))
                        schedule.append(action)
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.appData.autoPlaySchedule = schedule
            print("[DrumPlayer] Auto-play schedule built: \(schedule.count) events")
        }
    }
    
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
                delayMs = parsedFraction * wholeNoteMs
                rhythmicTime += delayMs
                physicalTime = rhythmicTime
            } else if let ms = Double(event.delay) {
                delayMs = ms
                physicalTime += delayMs
            } else { continue }
            newPatternSchedule.append((timestampMs: physicalTime, notes: event.notes))
        }
        return newPatternSchedule
    }
}
