import Foundation
import Combine

class DrumPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var appData: AppData

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPreviewing: Bool = false
    
    private enum PlaybackState { case stopped, playing }
    private var playbackState: PlaybackState = .stopped
    
    private var measureScheduler: DispatchWorkItem?
    private var beatDurationMs: Double = 0
    private var measureDurationMs: Double = 0
    private var startTimeMs: Double = 0
    
    private var previewTimer: Timer?

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
            print("[DrumPlayer] No active drum pattern selected.")
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
        
        print("[DrumPlayer] Playback started for pattern: \(pattern.name)")
        scheduleMeasure(measureIndex: 0, schedule: schedule, measureStartUptimeMs: self.startTimeMs)
    }
    
    func previewPattern(_ pattern: DrumPattern, bpm: Double) {
        if isPlaying || isPreviewing {
            stop()
            return
        }

        isPreviewing = true
        let stepDuration = 60.0 / bpm / Double(pattern.steps / 4) // Assuming 16th notes per bar
        var currentStep = 0

        previewTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self, self.isPreviewing else {
                timer.invalidate()
                return
            }

            for (instrumentIndex, instrumentRow) in pattern.patternGrid.enumerated() {
                if instrumentRow[currentStep] {
                    let midiNote = 36 + instrumentIndex // Basic mapping
                    self.scheduleMidiEvent(notes: [midiNote], at: ProcessInfo.processInfo.systemUptime * 1000.0, durationMs: 100)
                }
            }

            currentStep = (currentStep + 1) % pattern.steps
        }
    }

    private func scheduleMeasure(measureIndex: Int, schedule: [(timestampMs: Double, notes: [Int])], measureStartUptimeMs: Double) {
        for event in schedule {
            let scheduledOnUptimeMs = measureStartUptimeMs + event.timestampMs
            scheduleMidiEvent(notes: event.notes, at: scheduledOnUptimeMs)
        }

        let nextMeasureIndex = measureIndex + 1
        let nextMeasureStartUptimeMs = self.startTimeMs + (Double(nextMeasureIndex) * self.measureDurationMs)
        let nowMs = ProcessInfo.processInfo.systemUptime * 1000.0
        let delayUntilNextMeasureMs = max(0, nextMeasureStartUptimeMs - nowMs)

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.playbackState == .playing else { return }
            self.scheduleMeasure(measureIndex: nextMeasureIndex, schedule: schedule, measureStartUptimeMs: nextMeasureStartUptimeMs)
        }
        measureScheduler = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delayUntilNextMeasureMs / 1000.0, execute: work)
    }

    public func stop() {
        if playbackState == .stopped && !isPreviewing { return }
        print("[DrumPlayer] stopped")
        
        self.playbackState = .stopped
        self.isPlaying = false
        self.isPreviewing = false
        
        measureScheduler?.cancel()
        measureScheduler = nil
        previewTimer?.invalidate()
        previewTimer = nil

        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
    }
    
    private func buildSchedule(from pattern: DrumPattern, measureDurationMs: Double) -> [(timestampMs: Double, notes: [Int])] {
        var newSchedule: [(timestampMs: Double, notes: [Int])] = []
        let stepDurationMs = measureDurationMs / Double(pattern.steps)

        for step in 0..<pattern.steps {
            var notesForStep: [Int] = []
            for instrumentIndex in 0..<pattern.instruments.count {
                if pattern.patternGrid[instrumentIndex][step] {
                    let midiNote = 36 + instrumentIndex
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
