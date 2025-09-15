import Foundation
import Combine

class ChordPlayer: ObservableObject {
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    private var appData: AppData
    private var drumPlayer: DrumPlayer

    private let notesLock = NSRecursiveLock()

    private var playingNotes: [UInt8: UUID] = [:] // Maps MIDI Note -> Scheduled Note-Off Task ID
    private var stringNotes: [Int: UInt8] = [:] // Maps String Index (0-5) -> MIDI Note
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager, appData: AppData, drumPlayer: DrumPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.drumPlayer = drumPlayer

        drumPlayer.beatSubject
            .sink { [weak self] beat in
                // We can use this to trigger events on the beat
            }
            .store(in: &cancellables)
    }

    func previewPattern(_ pattern: GuitarPattern) {
        panic()
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        let previewPreset = Preset.createNew(name: "PreviewPreset")
        playChord(chord: previewChord, pattern: pattern, preset: previewPreset, quantization: .none)
    }

    func playChord(chord: Chord, pattern: GuitarPattern, preset: Preset, quantization: QuantizationMode, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        let schedulingStartUptimeMs = nextQuantizationTime(for: quantization)
        let delay = (schedulingStartUptimeMs - ProcessInfo.processInfo.systemUptime * 1000.0) / 1000.0

        schedulingQueue.asyncAfter(deadline: .now() + (delay > 0 ? delay : 0)) { [weak self] in
            guard let self = self else { return }

            let transpositionOffset = MusicTheory.KEY_CYCLE.firstIndex(of: preset.key) ?? 0

            var midiNotesForChord: [Int] = Array(repeating: -1, count: 6)
            let fretsForPlayback = Array(chord.frets.reversed())
            for (stringIndex, fret) in fretsForPlayback.enumerated() {
                if fret >= 0 {
                    midiNotesForChord[stringIndex] = MusicTheory.standardGuitarTuning[stringIndex] + fret + transpositionOffset
                }
            }

            let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
            let stepsPerWholeNote = pattern.resolution == .sixteenth ? 16.0 : 8.0
            let singleStepDurationSeconds = wholeNoteSeconds / stepsPerWholeNote

            DispatchQueue.main.async {
                self.updateCurrentlyPlayingUI(chordName: chord.name)
                self.stopSilentStrings(newChordMidiNotes: midiNotesForChord)
            }

            for (stepIndex, step) in pattern.steps.enumerated() {
                guard !step.activeNotes.isEmpty else { continue }

                let stepStartTimeOffsetMs = Double(stepIndex) * singleStepDurationSeconds * 1000.0
                let activeNotesInStep = step.activeNotes.compactMap { stringIndex -> (note: UInt8, stringIndex: Int)? in
                    guard midiNotesForChord[stringIndex] != -1 else { return nil }
                    return (note: UInt8(midiNotesForChord[stringIndex]), stringIndex: stringIndex)
                }

                guard !activeNotesInStep.isEmpty else { continue }

                let adaptiveVelocity = self.calculateAdaptiveVelocity(baseVelocity: velocity, noteCount: activeNotesInStep.count)

                switch step.type {
                case .rest:
                    break
                case .arpeggio:
                    let arpeggioStepDuration = singleStepDurationSeconds / Double(activeNotesInStep.count)
                    let sortedNotes = activeNotesInStep.sorted { $0.stringIndex > $1.stringIndex }
                    for (noteIndex, noteItem) in sortedNotes.enumerated() {
                        let noteStartTimeOffsetMs = Double(noteIndex) * arpeggioStepDuration * 1000.0
                        self.scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: velocity, startTimeMs: schedulingStartUptimeMs + stepStartTimeOffsetMs + noteStartTimeOffsetMs, durationSeconds: duration)
                    }
                case .strum:
                    let strumDelay = self.strumDelayInSeconds(for: step.strumSpeed)
                    let sortedNotes = activeNotesInStep.sorted { step.strumDirection == .down ? $0.stringIndex > $1.stringIndex : $0.stringIndex < $1.stringIndex }
                    for (noteIndex, noteItem) in sortedNotes.enumerated() {
                        let noteStartTimeOffsetMs = Double(noteIndex) * strumDelay * 1000.0
                        self.scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: adaptiveVelocity, startTimeMs: schedulingStartUptimeMs + stepStartTimeOffsetMs + noteStartTimeOffsetMs, durationSeconds: duration)
                    }
                }
            }
        }
    }
    
    private func nextQuantizationTime(for mode: QuantizationMode) -> Double {
        let now = ProcessInfo.processInfo.systemUptime * 1000.0
        if !drumPlayer.isPlaying || mode == .none {
            return now
        }

        let beatDurationMs = (60.0 / (appData.preset?.bpm ?? 120.0)) * 1000.0
        let beatsPerMeasure = appData.preset?.timeSignature.beatsPerMeasure ?? 4
        let measureDurationMs = beatDurationMs * Double(beatsPerMeasure)
        let halfMeasureDurationMs = measureDurationMs / 2.0

        let currentBeatInMeasure = drumPlayer.currentBeat
        let currentMeasureIndex = floor((now - drumPlayer.startTimeMs) / measureDurationMs)
        let currentMeasureStartTime = drumPlayer.startTimeMs + (currentMeasureIndex * measureDurationMs)

        switch mode {
        case .measure:
            return currentMeasureStartTime + measureDurationMs
        case .halfMeasure:
            let halfMeasures = floor((now - currentMeasureStartTime) / halfMeasureDurationMs)
            return currentMeasureStartTime + (halfMeasures + 1) * halfMeasureDurationMs
        case .none:
            return now
        }
    }

    private func strumDelayInSeconds(for speed: StrumSpeed) -> TimeInterval {
        switch speed {
        case .fast: return 0.01
        case .medium: return 0.025
        case .slow: return 0.05
        }
    }

    private func scheduleNote(note: UInt8, stringIndex: Int, velocity: UInt8, startTimeMs: Double, durationSeconds: TimeInterval) {
        notesLock.lock()
        defer { notesLock.unlock() }

        if let previousNote = self.stringNotes[stringIndex] {
            if let scheduledOffId = self.playingNotes[previousNote] {
                self.midiManager.cancelScheduledEvent(id: scheduledOffId)
                self.playingNotes.removeValue(forKey: previousNote)
            }
            self.midiManager.sendNoteOff(note: previousNote, velocity: 0, channel: UInt8(appData.chordMidiChannel - 1))
        }

        self.midiManager.scheduleNoteOn(note: note, velocity: velocity, channel: UInt8(appData.chordMidiChannel - 1), scheduledUptimeMs: startTimeMs)
        self.stringNotes[stringIndex] = note

        let scheduledNoteOffUptimeMs = startTimeMs + (durationSeconds * 1000.0)
        let offId = self.midiManager.scheduleNoteOff(note: note, velocity: 0, channel: UInt8(appData.chordMidiChannel - 1), scheduledUptimeMs: scheduledNoteOffUptimeMs)
        
        self.playingNotes[note] = offId
    }
    
    private func stopSilentStrings(newChordMidiNotes: [Int]) {
        notesLock.lock()
        defer { notesLock.unlock() }

        for (stringIndex, note) in stringNotes {
            if newChordMidiNotes[stringIndex] == -1 {
                if let scheduledOffId = playingNotes[note] {
                    midiManager.cancelScheduledEvent(id: scheduledOffId)
                    playingNotes.removeValue(forKey: note)
                }
                midiManager.sendNoteOff(note: note, velocity: 0, channel: UInt8(appData.chordMidiChannel - 1))
                stringNotes.removeValue(forKey: stringIndex)
            }
        }
    }
    
    private func updateCurrentlyPlayingUI(chordName: String) {
        DispatchQueue.main.async {
            self.appData.currentlyPlayingChordName = chordName
        }
    }

    func panic() {
        notesLock.lock()
        defer { notesLock.unlock() }

        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
        playingNotes.removeAll()
        stringNotes.removeAll()
    }
    
    private func calculateAdaptiveVelocity(baseVelocity: UInt8, noteCount: Int) -> UInt8 {
        guard noteCount > 1 else { return baseVelocity }
        let scalingFactor: Double = 1.2
        let reductionFactor = 1.0 / sqrt(Double(noteCount))
        let adaptiveVelocity = Double(baseVelocity) * reductionFactor * scalingFactor
        let clampedVelocity = max(1, min(127, Int(round(adaptiveVelocity))))
        return UInt8(clampedVelocity)
    }
}

class MusicTheory {
    static let standardGuitarTuning = [64, 59, 55, 50, 45, 40] // EADGBe (index 0 is high E)
    static let KEY_CYCLE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
}
