import Foundation
import Combine

class SoloPlayer: ObservableObject, Quantizable {
    // Dependencies
    private var midiManager: MidiManager
    var appData: AppData

    // Playback State
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0
    
    private var scheduledEventIDs: [UUID] = []
    private var playbackStartDate: Date?
    private var uiTimerCancellable: AnyCancellable?
    private var currentlyPlayingSegmentID: UUID?

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(note: SoloNote, offTime: Double)
        case bend(note: SoloNote, offTime: Double)
    }
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    var drumPlayer: DrumPlayer

    init(midiManager: MidiManager, appData: AppData, drumPlayer: DrumPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.drumPlayer = drumPlayer
    }

    func play(segment: SoloSegment, quantization: QuantizationMode) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stopPlayback()
            return
        }
        
        stopPlayback()

        let schedulingStartUptimeMs = nextQuantizationTime(for: quantization)
        let delay = (schedulingStartUptimeMs - ProcessInfo.processInfo.systemUptime * 1000.0) / 1000.0

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (delay > 0 ? delay : 0)) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentlyPlayingSegmentID = segment.id
            }

            let bpm = self.appData.preset?.bpm ?? 120.0
            let beatsToSeconds = 60.0 / bpm
            let playbackStartTimeMs = schedulingStartUptimeMs
            
            let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
            var consumedNoteIDs = Set<UUID>()
            var actions: [MusicalAction] = []
            
            let transposition = self.transposition(forKey: self.appData.preset?.key ?? "C")


            for i in 0..<notesSortedByTime.count {
                let currentNote = notesSortedByTime[i]
                if consumedNoteIDs.contains(currentNote.id) { continue }

                var noteOffTime = segment.lengthInBeats
                if let nextNoteOnSameString = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                    noteOffTime = nextNoteOnSameString.startTime
                }

                if currentNote.technique == .slide,
                   let slideTargetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                    
                    consumedNoteIDs.insert(slideTargetNote.id)
                    var slideOffTime = segment.lengthInBeats
                    if let targetIndex = notesSortedByTime.firstIndex(of: slideTargetNote), 
                       let nextNoteAfterSlide = notesSortedByTime.dropFirst(targetIndex + 1).first(where: { $0.string == currentNote.string }) {
                        slideOffTime = nextNoteAfterSlide.startTime
                    }
                    actions.append(.slide(from: currentNote, to: slideTargetNote, offTime: slideOffTime))

                } else if currentNote.technique == .vibrato {
                    actions.append(.vibrato(note: currentNote, offTime: noteOffTime))

                } else if currentNote.technique == .bend {
                    actions.append(.bend(note: currentNote, offTime: noteOffTime))

                } else {
                    actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                }
            }

            var eventIDs: [UUID] = []
            
            for action in actions {
                switch action {
                case .playNote(let note, let offTime):
                    guard note.fret >= 0 else { continue }
                    let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                    let velocity = UInt8(note.velocity)
                    let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                    let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                    if noteOffTimeMs > noteOnTimeMs {
                        eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs))
                        eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs))
                    }

                case .slide(let fromNote, let toNote, let offTime):
                    guard fromNote.fret >= 0, toNote.fret >= 0 else { continue }
                    let startMidiNote = self.midiNote(from: fromNote.string, fret: fromNote.fret, transposition: transposition)
                    let velocity = UInt8(fromNote.velocity)
                    let noteOnTimeMs = playbackStartTimeMs + (fromNote.startTime * beatsToSeconds * 1000.0)
                    let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                    eventIDs.append(self.midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, scheduledUptimeMs: noteOnTimeMs))

                    let slideDurationBeats = toNote.startTime - fromNote.startTime
                    if slideDurationBeats > 0 {
                        let pitchBendSteps = max(2, Int(slideDurationBeats * beatsToSeconds * 50))
                        let fretDifference = toNote.fret - fromNote.fret
                        let pitchBendRangeSemitones = 2.0
                        let finalPitchBendValue = 8192 + Int(Double(fretDifference) * (8191.0 / pitchBendRangeSemitones))

                        for step in 0...pitchBendSteps {
                            let t = Double(step) / Double(pitchBendSteps)
                            let bendTimeMs = playbackStartTimeMs + ((fromNote.startTime + t * slideDurationBeats) * beatsToSeconds * 1000.0)
                            let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                            eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(intermediatePitch), scheduledUptimeMs: bendTimeMs))
                        }
                    }
                    
                    eventIDs.append(self.midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, scheduledUptimeMs: noteOffTimeMs))
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1))

                case .vibrato(let note, let offTime):
                    guard note.fret >= 0 else { continue }
                    let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                    let velocity = UInt8(note.velocity)
                    let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                    let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                    eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs))

                    let vibratoDurationBeats = offTime - note.startTime
                    if vibratoDurationBeats > 0.1 {
                        let vibratoRateHz = 5.5
                        let vibratoIntensity = note.articulation?.vibratoIntensity ?? 0.5
                        let maxBendSemitones = 0.4
                        let pitchBendRangeSemitones = 2.0
                        let maxPitchBendAmount = (maxBendSemitones / pitchBendRangeSemitones) * 8191.0 * vibratoIntensity
                        let totalCycles = vibratoDurationBeats * beatsToSeconds * vibratoRateHz
                        let totalSteps = Int(totalCycles * 12.0)

                        if totalSteps > 0 {
                            for step in 0...totalSteps {
                                let t_duration = Double(step) / Double(totalSteps)
                                let t_angle = t_duration * totalCycles * 2.0 * .pi
                                let sineValue = sin(t_angle)
                                let pitchBendValue = 8192 + Int(sineValue * maxPitchBendAmount)
                                let bendTimeMs = playbackStartTimeMs + ((note.startTime + t_duration * vibratoDurationBeats) * beatsToSeconds * 1000.0)
                                eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(pitchBendValue), scheduledUptimeMs: bendTimeMs))
                            }
                        }
                    }

                    eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs))
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1))
                    
                case .bend(let note, let offTime):
                    guard note.fret >= 0 else { continue }
                    let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                    let velocity = UInt8(note.velocity)
                    let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                    let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                    eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs))

                    let bendAmountSemitones = note.articulation?.bendAmount ?? 1.0
                    if bendAmountSemitones > 0 {
                        let bendDurationBeats = 0.1 / beatsToSeconds
                        let pitchBendRangeSemitones = 2.0
                        let finalPitchBendValue = 8192 + Int(bendAmountSemitones * (8191.0 / pitchBendRangeSemitones))
                        
                        for step in 0...10 {
                            let t = Double(step) / 10.0
                            let bendTimeMs = playbackStartTimeMs + ((note.startTime + t * bendDurationBeats) * beatsToSeconds * 1000.0)
                            if bendTimeMs < noteOffTimeMs {
                                let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                                eventIDs.append(self.midiManager.schedulePitchBend(value: UInt16(intermediatePitch), scheduledUptimeMs: bendTimeMs))
                            }
                        }
                    }

                    eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs))
                    eventIDs.append(self.midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1))
                }
            }
            self.scheduledEventIDs = eventIDs

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
        isPlaying = false
        currentlyPlayingSegmentID = nil
        midiManager.cancelAllPendingScheduledEvents()
        midiManager.sendPitchBend(value: 8192)
        midiManager.sendPanic()
        scheduledEventIDs.removeAll()
        uiTimerCancellable?.cancel()
        playbackStartDate = nil
        playbackPosition = 0
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
