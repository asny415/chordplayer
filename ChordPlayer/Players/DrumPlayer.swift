import Foundation
import Combine

class DrumPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var appData: AppData

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPreviewing: Bool = false
    @Published private(set) var currentBeat: Int = 0

    private enum PlaybackState { case stopped, playing }
    private var playbackState: PlaybackState = .stopped

    private var beatScheduler: DispatchWorkItem?
    private var beatDurationMs: Double = 0
    private var measureDurationMs: Double = 0
    var startTimeMs: Double = 0
    private var currentMeasureIndex: Int = 0
    private(set) var lastBeatTime: Double = 0

    private var previewTimer: Timer?

    let beatSubject = PassthroughSubject<Int, Never>()

    init(midiManager: MidiManager, appData: AppData) {
        self.midiManager = midiManager
        self.appData = appData
    }

    func playNote(midiNote: Int) {
        let channel = UInt8(appData.drumMidiChannel - 1)
        midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100, channel: channel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 0, channel: channel)
        }
    }

    func playActivePattern() {
        guard let preset = appData.preset, let activePatternId = preset.activeDrumPatternId else {
            return
        }
        
        if let pattern = preset.drumPatterns.first(where: { $0.id == activePatternId }) {
            playPattern(pattern, preset: preset)
        }
    }

    func playPattern(_ pattern: DrumPattern, preset: Preset) {
        if playbackState == .playing {
            stop()
        }

        let beatsPerMeasure = preset.timeSignature.beatsPerMeasure
        let quarterNoteDurationMs = (60.0 / preset.bpm) * 1000.0
        self.beatDurationMs = quarterNoteDurationMs
        self.measureDurationMs = Double(beatsPerMeasure) * beatDurationMs
        self.startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        
        let schedule = buildSchedule(from: pattern, measureDurationMs: measureDurationMs)

        self.playbackState = .playing
        self.isPlaying = true
        
        scheduleBeat(beatIndex: 0, schedule: schedule, measureDurationMs: measureDurationMs)
    }
    
    func previewPattern(_ pattern: DrumPattern, bpm: Double) {
        if isPlaying || isPreviewing {
            stop()
            return
        }

        isPreviewing = true
        let stepDuration = 60.0 / bpm / Double(pattern.length / 4) // Assuming 16th notes per bar
        var currentStep = 0

        previewTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self, self.isPreviewing else {
                timer.invalidate()
                return
            }

            for (instrumentIndex, instrumentRow) in pattern.patternGrid.enumerated() {
                if instrumentRow[currentStep] {
                    let midiNote = pattern.midiNotes[instrumentIndex]
                    self.scheduleMidiEvent(notes: [midiNote], at: ProcessInfo.processInfo.systemUptime * 1000.0, durationMs: 100)
                }
            }

            currentStep = (currentStep + 1) % pattern.length
        }
    }

    private func scheduleBeat(beatIndex: Int, schedule: [(timestampMs: Double, notes: [Int])], measureDurationMs: Double) {
        let measureIndex = beatIndex / appData.preset!.timeSignature.beatsPerMeasure
        let beatInMeasure = beatIndex % appData.preset!.timeSignature.beatsPerMeasure

        self.lastBeatTime = ProcessInfo.processInfo.systemUptime * 1000.0

        DispatchQueue.main.async {
            self.currentBeat = beatInMeasure + 1
        }
        beatSubject.send(beatInMeasure + 1)

        let measureStartUptimeMs = self.startTimeMs + (Double(measureIndex) * measureDurationMs)

        for event in schedule {
            if floor(event.timestampMs / beatDurationMs) == Double(beatInMeasure) {
                let scheduledOnUptimeMs = measureStartUptimeMs + event.timestampMs
                scheduleMidiEvent(notes: event.notes, at: scheduledOnUptimeMs)
            }
        }

        let nextBeatIndex = beatIndex + 1
        let nextBeatStartUptimeMs = self.startTimeMs + (Double(nextBeatIndex) * self.beatDurationMs)
        let nowMs = ProcessInfo.processInfo.systemUptime * 1000.0
        let delayUntilNextBeatMs = max(0, nextBeatStartUptimeMs - nowMs)

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.playbackState == .playing else { return }
            self.scheduleBeat(beatIndex: nextBeatIndex, schedule: schedule, measureDurationMs: measureDurationMs)
        }
        beatScheduler = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delayUntilNextBeatMs / 1000.0, execute: work)
    }

    public func stop() {
        if playbackState == .stopped && !isPreviewing { return }
        
        self.playbackState = .stopped
        self.isPlaying = false
        self.isPreviewing = false
        
        beatScheduler?.cancel()
        beatScheduler = nil
        previewTimer?.invalidate()
        previewTimer = nil

        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
    }
    
    private func buildSchedule(from pattern: DrumPattern, measureDurationMs: Double) -> [(timestampMs: Double, notes: [Int])] {
        var newSchedule: [(timestampMs: Double, notes: [Int])] = []
        let stepDurationMs = measureDurationMs / Double(pattern.length)

        for step in 0..<pattern.length {
            var notesForStep: [Int] = []
            for instrumentIndex in 0..<pattern.instruments.count {
                if pattern.patternGrid[instrumentIndex][step] {
                    let midiNote = pattern.midiNotes[instrumentIndex]
                    notesForStep.append(midiNote)
                }
            }
            
            if !notesForStep.isEmpty {
                let timestampMs = Double(step) * stepDurationMs
                newSchedule.append((timestampMs: timestampMs, notes: notesForStep))
            }
        }
        return newSchedule
    }
    
    private func scheduleMidiEvent(notes: [Int], at timeMs: Double, velocity: UInt8 = 100, durationMs: Double = 100) {
        let channel = UInt8(appData.drumMidiChannel - 1)
        for note in notes {
            midiManager.scheduleNoteOn(note: UInt8(note), velocity: velocity, channel: channel, scheduledUptimeMs: timeMs)
            midiManager.scheduleNoteOff(note: UInt8(note), velocity: 0, channel: channel, scheduledUptimeMs: timeMs + durationMs)
        }
    }
}
