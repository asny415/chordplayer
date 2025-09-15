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
        // Stop any currently playing notes before starting a preview.
        panic()

        // Create a generic chord and preset for previewing.
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        let previewPreset = Preset.createNew(name: "PreviewPreset") // BPM defaults to 120

        // Use the main playing logic for the preview.
        playChord(chord: previewChord, pattern: pattern, preset: previewPreset)
    }

    /// Plays a chord using a given pattern, based on the new data models.
    func playChord(chord: Chord, pattern: GuitarPattern, preset: Preset, velocity: UInt8 = 100, duration: TimeInterval = 0.5) {
        
        // 1. Calculate the MIDI notes for the given chord definition
        var midiNotesForChord: [Int] = Array(repeating: -1, count: 6)
        for (stringIndex, fret) in chord.frets.enumerated() {
            if fret >= 0 { // -1 means muted string
                // TODO: Re-implement transposition based on preset key
                midiNotesForChord[stringIndex] = MusicTheory.standardGuitarTuning[stringIndex] + fret
            }
        }

        // 2. Calculate timing based on tempo
        let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
        let singleStepDurationSeconds = wholeNoteSeconds / Double(pattern.steps)
        let schedulingStartUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0

        // 3. Schedule UI update to be in sync with audio
        scheduledUIUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.appData.currentlyPlayingChordName = chord.name
            // TODO: Update this if we add a pattern name display
            // self?.appData.currentlyPlayingPatternName = pattern.name
        }
        scheduledUIUpdateWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)

        // 4. Stop notes on strings that will be silent in the new chord.
        stopSilentStrings(newChordMidiNotes: midiNotesForChord)

        // 5. Iterate over the pattern grid and schedule notes
        for step in 0..<pattern.steps {
            var notesToScheduleInStep: [(note: UInt8, stringIndex: Int)] = []
            
            for stringIndex in 0..<pattern.strings {
                // Check if the pattern has a note at this step and string
                if pattern.patternGrid[stringIndex][step] {
                    let midiNote = midiNotesForChord[stringIndex]
                    if midiNote != -1 {
                        notesToScheduleInStep.append((note: UInt8(midiNote), stringIndex: stringIndex))
                    }
                }
            }
            
            if !notesToScheduleInStep.isEmpty {
                let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocity, noteCount: notesToScheduleInStep.count)
                let eventTimeMs = schedulingStartUptimeMs + (Double(step) * singleStepDurationSeconds * 1000.0)
                
                for item in notesToScheduleInStep {
                    scheduleNote(note: item.note, stringIndex: item.stringIndex, velocity: adaptiveVelocity, startTimeMs: eventTimeMs, durationSeconds: duration)
                }
            }
        }
    }
    
    private func scheduleNote(note: UInt8, stringIndex: Int, velocity: UInt8, startTimeMs: Double, durationSeconds: TimeInterval) {
        // If a note is already playing on this string, cancel its scheduled note-off and send an immediate NoteOff.
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
            if newChordMidiNotes[stringIndex] == -1 { // If the string is muted in the new chord
                if let scheduledOffId = playingNotes[note] {
                    midiManager.cancelScheduledEvent(id: scheduledOffId)
                    playingNotes.removeValue(forKey: note)
                }
                midiManager.sendNoteOff(note: note, velocity: 0, channel: UInt8(appData.chordMidiChannel - 1))
                stringNotes.removeValue(forKey: stringIndex)
            }
        }
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

// TODO: Move this to a more appropriate location
class MusicTheory {
    static let standardGuitarTuning = [64, 59, 55, 50, 45, 40] // EADGBe
}