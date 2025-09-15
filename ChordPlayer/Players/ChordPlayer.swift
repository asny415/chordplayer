import Foundation
import Combine

class ChordPlayer: ObservableObject {
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    private var appData: AppData

    private var playingNotes: [UInt8: UUID] = [:] // Maps MIDI Note -> Scheduled Note-Off Task ID
    private var stringNotes: [Int: UInt8] = [:] // Maps String Index (0-5) -> MIDI Note
    private var scheduledUIUpdateWorkItem: DispatchWorkItem?

    init(midiManager: MidiManager, appData: AppData) {
        self.midiManager = midiManager
        self.appData = appData
    }

    func previewPattern(_ pattern: GuitarPattern) {
        panic()
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        let previewPreset = Preset.createNew(name: "PreviewPreset")
        playChord(chord: previewChord, pattern: pattern, preset: previewPreset)
    }

    func playChord(chord: Chord, pattern: GuitarPattern, preset: Preset, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        var midiNotesForChord: [Int] = Array(repeating: -1, count: 6)
        for (stringIndex, fret) in chord.frets.enumerated() {
            if fret >= 0 {
                midiNotesForChord[stringIndex] = MusicTheory.standardGuitarTuning[stringIndex] + fret
            }
        }

        let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
        let stepsPerWholeNote = pattern.resolution == .sixteenth ? 16.0 : 8.0
        let singleStepDurationSeconds = wholeNoteSeconds / stepsPerWholeNote
        let schedulingStartUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0

        updateCurrentlyPlayingUI(chordName: chord.name)
        stopSilentStrings(newChordMidiNotes: midiNotesForChord)

        for (stepIndex, step) in pattern.steps.enumerated() {
            guard !step.activeNotes.isEmpty else { continue }
            
            let stepStartTimeMs = schedulingStartUptimeMs + (Double(stepIndex) * singleStepDurationSeconds * 1000.0)
            let activeNotesInStep = step.activeNotes.compactMap { stringIndex -> (note: UInt8, stringIndex: Int)? in
                guard midiNotesForChord[stringIndex] != -1 else { return nil }
                return (note: UInt8(midiNotesForChord[stringIndex]), stringIndex: stringIndex)
            }

            guard !activeNotesInStep.isEmpty else { continue }
            
            let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocity, noteCount: activeNotesInStep.count)

            switch step.type {
            case .rest:
                break // Do nothing

            case .arpeggio:
                let arpeggioStepDuration = singleStepDurationSeconds / Double(activeNotesInStep.count)
                // Sort by string index for consistent playback (e.g., high to low)
                let sortedNotes = activeNotesInStep.sorted { $0.stringIndex > $1.stringIndex }
                for (noteIndex, noteItem) in sortedNotes.enumerated() {
                    let noteStartTimeMs = stepStartTimeMs + (Double(noteIndex) * arpeggioStepDuration * 1000.0)
                    scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: velocity, startTimeMs: noteStartTimeMs, durationSeconds: duration)
                }

            case .strum:
                let strumDelay = strumDelayInSeconds(for: step.strumSpeed)
                let sortedNotes = activeNotesInStep.sorted { step.strumDirection == .down ? $0.stringIndex > $1.stringIndex : $0.stringIndex < $1.stringIndex }
                
                for (noteIndex, noteItem) in sortedNotes.enumerated() {
                    let noteStartTimeMs = stepStartTimeMs + (Double(noteIndex) * strumDelay * 1000.0)
                    scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: adaptiveVelocity, startTimeMs: noteStartTimeMs, durationSeconds: duration)
                }
            }
        }
    }
    
    private func strumDelayInSeconds(for speed: StrumSpeed) -> TimeInterval {
        switch speed {
        case .fast: return 0.01 // 10ms
        case .medium: return 0.025 // 25ms
        case .slow: return 0.05 // 50ms
        }
    }

    private func scheduleNote(note: UInt8, stringIndex: Int, velocity: UInt8, startTimeMs: Double, durationSeconds: TimeInterval) {
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
        scheduledUIUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.appData.currentlyPlayingChordName = chordName
        }
        scheduledUIUpdateWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func panic() {
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
}
