import Foundation
import Combine

class SoloPlayer: ObservableObject, Quantizable {
    // Dependencies
    private var midiManager: MidiManager
    var appData: AppData

    // Playback State
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0
    
    private var activeNotes: Set<UInt8> = []
    private var scheduledEventIDs: [UUID] = []
    private var playbackStartDate: Date?
    private var uiTimerCancellable: AnyCancellable?
    private var currentlyPlayingSegmentID: UUID?

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(note: SoloNote, offTime: Double)
        case bend(from: SoloNote, to: SoloNote, offTime: Double)
    }
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    var drumPlayer: DrumPlayer

    init(midiManager: MidiManager, appData: AppData, drumPlayer: DrumPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.drumPlayer = drumPlayer
    }

    func play(segment: SoloSegment, quantization: QuantizationMode, channel: UInt8 = 0) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stopPlayback()
            return
        }
        
        stopPlayback()

        let schedulingStartUptimeMs = nextQuantizationTime(for: quantization)
        let delay = (schedulingStartUptimeMs - ProcessInfo.processInfo.systemUptime * 1000.0) / 1000.0

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (delay > 0 ? delay : 0)) { [weak self] in
            guard let self = self else { return }

            // Set the pitch bend range for the channel before playing
            print("[SOLO DEBUG] Setting pitch bend range to +/- 2 semitones on channel \(channel)")
            self.midiManager.setPitchBendRange(channel: channel, rangeInSemitones: 2)

            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentlyPlayingSegmentID = segment.id
            }

            let bpm = self.appData.preset?.bpm ?? 120.0
            let beatsToSeconds = 60.0 / bpm
            let playbackStartTime = schedulingStartUptimeMs / 1000.0
            
            let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
            let transposition = self.transposition(forKey: self.appData.preset?.key ?? "C")

            var consumedNoteIDs = Set<UUID>()
            var actions: [MusicalAction] = []

            // 1. Build a list of `MusicalAction`s
            for i in 0..<notesSortedByTime.count {
                let currentNote = notesSortedByTime[i]
                if consumedNoteIDs.contains(currentNote.id) || currentNote.fret < 0 { continue }

                let noteOffTime: Double
                if let nextNoteOnSameString = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                    noteOffTime = nextNoteOnSameString.startTime
                } else {
                    noteOffTime = currentNote.startTime + (currentNote.duration ?? 1.0)
                }

                switch currentNote.technique {
                case .slide:
                    if let targetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                        consumedNoteIDs.insert(targetNote.id)
                        let slideOffTime = targetNote.startTime + (targetNote.duration ?? 1.0)
                        actions.append(.slide(from: currentNote, to: targetNote, offTime: slideOffTime))
                    } else {
                        actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                    }
                
                case .bend:
                    if let targetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                        consumedNoteIDs.insert(targetNote.id)
                        let bendOffTime = targetNote.startTime + (targetNote.duration ?? 1.0)
                        actions.append(.bend(from: currentNote, to: targetNote, offTime: bendOffTime))
                    } else {
                        actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                    }

                case .vibrato:
                    actions.append(.vibrato(note: currentNote, offTime: noteOffTime))

                case .normal:
                    actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                }
            }
            
            var allEventIDs: [UUID] = []
            self.activeNotes.removeAll()

            // 2. Process the actions and schedule MIDI events
            for action in actions {
                var eventIDs: [UUID] = []
                let midiChannel = channel
                let velocity = UInt8(min(127, max(1, 100))) // Default velocity for now

                switch action {
                case .playNote(let note, let offTime):
                    let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                    let noteOnTimeMs = (playbackStartTime + note.startTime * beatsToSeconds) * 1000
                    let noteOffTimeMs = (playbackStartTime + offTime * beatsToSeconds) * 1000

                    if noteOffTimeMs > noteOnTimeMs {
                        eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTimeMs))
                        eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeMs))
                        self.activeNotes.insert(midiNoteNumber)
                    }

                case .slide(let fromNote, let toNote, let offTime):
                    print("[SOLO DEBUG] Slide action detected: From Fret \(fromNote.fret) to \(toNote.fret) on string \(fromNote.string)")
                    let startMidiNote = self.midiNote(from: fromNote.string, fret: fromNote.fret, transposition: transposition)
                    let endMidiNote = self.midiNote(from: toNote.string, fret: toNote.fret, transposition: transposition)

                    let semitoneDifference = Int(endMidiNote) - Int(startMidiNote)
                    let pitchBendRangeSemitones = 2.0 // Standard pitch bend range
                    print("[SOLO DEBUG]   - Semitone difference: \(semitoneDifference)")

                    let noteOnTime = playbackStartTime + fromNote.startTime * beatsToSeconds
                    let slideTargetTime = playbackStartTime + toNote.startTime * beatsToSeconds
                    let finalNoteOffTime = playbackStartTime + offTime * beatsToSeconds
                    print("[SOLO DEBUG]   - Timings: NoteOn=\(noteOnTime), SlideTarget=\(slideTargetTime), NoteOff=\(finalNoteOffTime)")

                    // Pluck the first note
                    eventIDs.append(self.midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))
                    self.activeNotes.insert(startMidiNote)
                    print("[SOLO DEBUG]   - Scheduled NoteOn for \(startMidiNote) at \(noteOnTime * 1000)")

                    // --- Smooth pitch bend ---
                    let slideDurationSeconds = slideTargetTime - noteOnTime
                    if slideDurationSeconds > 0.01 && abs(semitoneDifference) > 0 {
                        print("[SOLO DEBUG]   - Scheduling pitch bend over \(slideDurationSeconds)s")
                        let finalPitchBendValue = 8192 + Int(Double(semitoneDifference) * (8191.0 / pitchBendRangeSemitones))
                        let pitchBendSteps = max(2, Int(slideDurationSeconds * 100)) // More steps for smoother slide
                        
                        for step in 0...pitchBendSteps {
                            let t = Double(step) / Double(pitchBendSteps)
                            let bendTimeMs = (noteOnTime + t * slideDurationSeconds) * 1000
                            let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                            let clampedPitch = max(0, min(16383, intermediatePitch))
                            eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(clampedPitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                            if step == 0 || step == pitchBendSteps { // Log first and last bend
                                print("[SOLO DEBUG]     - Bend step \(step): value=\(clampedPitch) at \(bendTimeMs)")
                            }
                        }
                    }
                    
                    // The bent note (startMidiNote) is held until the final off time
                    eventIDs.append(self.midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: finalNoteOffTime * 1000))
                    print("[SOLO DEBUG]   - Scheduled NoteOff for \(startMidiNote) at \(finalNoteOffTime * 1000)")

                    // Reset bend slightly after the note is off
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (finalNoteOffTime + 0.01) * 1000))
                    print("[SOLO DEBUG]   - Scheduled Pitch Bend Reset at \((finalNoteOffTime + 0.01) * 1000)")
                
                case .vibrato(let note, let offTime):
                    let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                    let noteOnTime = playbackStartTime + note.startTime * beatsToSeconds
                    let noteOffTimeAbsolute = playbackStartTime + offTime * beatsToSeconds

                    eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))
                    self.activeNotes.insert(midiNoteNumber)

                    let vibratoDurationSeconds = noteOffTimeAbsolute - noteOnTime
                    if vibratoDurationSeconds > 0.1 {
                        let vibratoRateHz = 5.0
                        let maxBendSemitones = 0.4
                        let pitchBendRangeSemitones = 2.0
                        let maxPitchBendAmount = (maxBendSemitones / pitchBendRangeSemitones) * 8191.0
                        let totalCycles = vibratoDurationSeconds * vibratoRateHz
                        let totalSteps = Int(totalCycles * 20.0) // 20 steps per cycle for smoothness

                        if totalSteps > 0 {
                            for step in 0...totalSteps {
                                let t_duration = Double(step) / Double(totalSteps)
                                let t_angle = t_duration * totalCycles * 2.0 * .pi
                                let sineValue = sin(t_angle)
                                let pitchBendValue = 8192 + Int(sineValue * maxPitchBendAmount)
                                let bendTimeMs = (noteOnTime + t_duration * vibratoDurationSeconds) * 1000
                                eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(pitchBendValue), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                            }
                        }
                    }

                    eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeAbsolute * 1000))
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (noteOffTimeAbsolute + 0.01) * 1000))

                case .bend(let fromNote, let toNote, let offTime):
                    let startMidiNote = self.midiNote(from: fromNote.string, fret: fromNote.fret, transposition: transposition)
                    let noteOnTime = playbackStartTime + fromNote.startTime * beatsToSeconds
                    let noteOffTimeAbsolute = playbackStartTime + offTime * beatsToSeconds

                    eventIDs.append(self.midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))
                    self.activeNotes.insert(startMidiNote)

                    let intervalBeats = toNote.startTime - fromNote.startTime
                    if intervalBeats > 0.1 {
                        // Perform a classic "bend and release" within the note's duration
                        let quarterIntervalBeats = intervalBeats / 4.0
                        
                        let bendUpStartTimeBeats = fromNote.startTime + quarterIntervalBeats
                        let bendUpDurationBeats = quarterIntervalBeats
                        
                        let releaseStartTimeBeats = bendUpStartTimeBeats + bendUpDurationBeats
                        let releaseDurationBeats = quarterIntervalBeats

                        let bendAmountSemitones = 2.0 // Bend up by a whole step
                        let pitchBendRangeSemitones = 2.0
                        let finalPitchBendValue = 8192 + Int(bendAmountSemitones * (8191.0 / pitchBendRangeSemitones))
                        
                        let pitchBendSteps = 10

                        // Bend Up
                        for step in 0...pitchBendSteps {
                            let t = Double(step) / Double(pitchBendSteps)
                            let bendTimeMs = (playbackStartTime + (bendUpStartTimeBeats + t * bendUpDurationBeats) * beatsToSeconds) * 1000
                            let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                            eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(intermediatePitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                        }

                        // Bend Down (Release)
                        for step in 0...pitchBendSteps {
                            let t = Double(step) / Double(pitchBendSteps)
                            let bendTimeMs = (playbackStartTime + (releaseStartTimeBeats + t * releaseDurationBeats) * beatsToSeconds) * 1000
                            let intermediatePitch = finalPitchBendValue - Int(Double(finalPitchBendValue - 8192) * t)
                            eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(intermediatePitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                        }
                    }

                    eventIDs.append(self.midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeAbsolute * 1000))
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (noteOffTimeAbsolute + 0.01) * 1000))
                }
                allEventIDs.append(contentsOf: eventIDs)
            }

            self.scheduledEventIDs = allEventIDs

            DispatchQueue.main.async {
                self.playbackStartDate = Date()
                self.uiTimerCancellable = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self = self, let startDate = self.playbackStartDate else { return }
                    let elapsedSeconds = Date().timeIntervalSince(startDate)
                    let beatsPerSecond = (self.appData.preset?.bpm ?? 120.0) / 60.0
                    self.playbackPosition = elapsedSeconds * beatsPerSecond
                    
                    if self.playbackPosition > segment.lengthInBeats {
                        self.stopPlayback()
                    }
                }
            }
        }
    }


    func stopPlayback() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
            self.uiTimerCancellable?.cancel()
            self.playbackStartDate = nil
            self.playbackPosition = 0
        }
        
        midiManager.cancelAllPendingScheduledEvents()
        
        // Send Note Off for all notes that were scheduled to play
        for note in activeNotes {
            midiManager.sendNoteOff(note: note, velocity: 0)
        }
        
        midiManager.sendPitchBend(value: 8192) // Reset pitch bend
        
        activeNotes.removeAll()
        scheduledEventIDs.removeAll()
    }
    
    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        // The notes in SoloSegment are relative to C major scale.
        // We need to transpose them to the preset's key.
        // The transposition should be `keyMap[key] ?? 0`.
        // For example, if the key is "D", the transposition is 2.
        // A C note (fret 1 on string 1) should become a D note.
        // The midi note for C is 60. The midi note for D is 62.
        // So we need to add 2 to the midi note.
        return keyMap[key] ?? 0
    }

    private func midiNote(from string: Int, fret: Int, transposition: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        let baseNote = openStringMIDINotes[string] + UInt8(fret)
        return baseNote + UInt8(transposition)
    }

    
}
