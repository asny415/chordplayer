import Foundation
import Combine
import AudioToolbox

class ChordPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    var appData: AppData

    // MARK: - Playback State
    @Published var isPlaying: Bool = false
    private var currentlyPlayingSegmentID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        
        // Subscribe to sequencer's isPlaying state
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            if !sequencerIsPlaying {
                self?.isPlaying = false
                self?.currentlyPlayingSegmentID = nil
            }
        }.store(in: &cancellables)
    }

    // MARK: - Public Playback Methods

    func play(segment: AccompanimentSegment) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stop()
            return
        }
        
        stop() // Stop any previous playback

        let channel = UInt8((appData.chordMidiChannel) - 1)
        midiManager.setPitchBendRange(channel: channel)

        guard let song = createSong(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[ChordPlayer] Failed to create song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: song, on: endpoint)
        
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func previewPattern(_ pattern: GuitarPattern, midiChannel: Int) {
        stop()
        
        let channel = UInt8(midiChannel - 1)
        guard let sequence = createSequenceForPattern(pattern, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[ChordPlayer] Failed to create preview sequence or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(sequence: sequence, on: endpoint)
        
        // For preview, we don't manage the isPlaying state in the same way
    }

    func stop() {
        midiSequencer.stop()
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
        }
    }

    func playSingle(chord: Chord, withPattern pattern: GuitarPattern) {
        stop()
        
        let channel = UInt8((appData.chordMidiChannel) - 1)
        guard let preset = appData.preset else { return }

        // Create a sequence for this single chord/pattern combo
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return }

        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        var musicTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &musicTrack)
        guard status == noErr, let track = musicTrack else { return }
        
        let patternDurationBeats = Double(pattern.length) * (pattern.activeResolution == .sixteenth ? 0.25 : 0.5)

        addPatternToTrack(
            track,
            chord: chord,
            pattern: pattern,
            preset: preset,
            patternStartBeat: 0.0,
            patternDurationBeats: patternDurationBeats,
            dynamics: .medium, // Default dynamics for single play
            midiChannel: channel
        )
        
        guard let endpoint = midiManager.selectedOutput else {
            print("[ChordPlayer] Failed to get MIDI endpoint for single play.")
            return
        }
        
        midiSequencer.play(sequence: sequence, on: endpoint)
    }

    // MARK: - Sequence Creation

    private func createSong(from segment: AccompanimentSegment, onChannel midiChannel: UInt8) -> MusicSong? {
        guard let preset = appData.preset else { return nil }
        
        var allNotes: [MusicNote] = []

        let absoluteChordEvents = segment.measures.enumerated().flatMap { (measureIndex, measure) -> [TimelineEvent] in
            measure.chordEvents.map { event in
                var absoluteEvent = event
                absoluteEvent.startBeat += measureIndex * preset.timeSignature.beatsPerMeasure
                return absoluteEvent
            }
        }.sorted { $0.startBeat < $1.startBeat }

        for (measureIndex, measure) in segment.measures.enumerated() {
            for patternEvent in measure.patternEvents {
                let absolutePatternStartBeatInt = measureIndex * preset.timeSignature.beatsPerMeasure + patternEvent.startBeat
                let activeChordEvent = absoluteChordEvents.last { $0.startBeat <= absolutePatternStartBeatInt }

                guard let chordEvent = activeChordEvent,
                      let chordToPlay = preset.chords.first(where: { $0.id == chordEvent.resourceId }),
                      let patternToPlay = preset.playingPatterns.first(where: { $0.id == patternEvent.resourceId }) else {
                    continue
                }
                
                let notesForPattern = createNotesForPattern(
                    chord: chordToPlay,
                    pattern: patternToPlay,
                    preset: preset,
                    patternStartBeat: Double(absolutePatternStartBeatInt),
                    patternDurationBeats: Double(patternEvent.durationInBeats),
                    dynamics: measure.dynamics
                )
                allNotes.append(contentsOf: notesForPattern)
            }
        }
        
        let track = SongTrack(instrumentName: "Accompaniment", midiChannel: Int(midiChannel), notes: allNotes)
        let song = MusicSong(tempo: preset.bpm, key: preset.key, timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit), tracks: [track])
        return song
    }

    func createSequence(from segment: AccompanimentSegment, onChannel midiChannel: UInt8) -> MusicSequence? {
        guard let preset = appData.preset else { return nil }
        
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }

        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        var musicTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &musicTrack)
        guard status == noErr, let track = musicTrack else { return nil }

        // Create a flat map of all chord events with their absolute INT beat.
        let absoluteChordEvents = segment.measures.enumerated().flatMap { (measureIndex, measure) -> [TimelineEvent] in
            measure.chordEvents.map { event in
                var absoluteEvent = event
                absoluteEvent.startBeat += measureIndex * preset.timeSignature.beatsPerMeasure
                return absoluteEvent
            }
        }.sorted { $0.startBeat < $1.startBeat }

        // Iterate through each measure and its pattern events.
        for (measureIndex, measure) in segment.measures.enumerated() {
            for patternEvent in measure.patternEvents {
                // Calculate the absolute start beat of the pattern event as an Int first.
                let absolutePatternStartBeatInt = measureIndex * preset.timeSignature.beatsPerMeasure + patternEvent.startBeat
                
                // Find the chord that should be active for this pattern event.
                let activeChordEvent = absoluteChordEvents.last { $0.startBeat <= absolutePatternStartBeatInt }

                guard let chordEvent = activeChordEvent,
                      let chordToPlay = preset.chords.first(where: { $0.id == chordEvent.resourceId }),
                      let patternToPlay = preset.playingPatterns.first(where: { $0.id == patternEvent.resourceId }) else {
                    continue
                }
                
                // Now, create the Double value for the music sequence.
                let absolutePatternStartBeatDouble = Double(absolutePatternStartBeatInt)
                
                addPatternToTrack(
                    track,
                    chord: chordToPlay,
                    pattern: patternToPlay,
                    preset: preset,
                    patternStartBeat: absolutePatternStartBeatDouble, // Correctly a Double
                    patternDurationBeats: Double(patternEvent.durationInBeats), // Correctly cast from Int
                    dynamics: measure.dynamics,
                    midiChannel: midiChannel
                )
            }
        }
        return sequence
    }
    
    func createSequenceForPattern(_ pattern: GuitarPattern, onChannel midiChannel: UInt8) -> MusicSequence? {
        guard let preset = appData.preset else { return nil }
        
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }

        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        var musicTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &musicTrack)
        guard status == noErr, let track = musicTrack else { return nil }
        
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        let patternDurationBeats = Double(pattern.length) * (pattern.resolution == .sixteenth ? 0.25 : 0.5)

        addPatternToTrack(
            track,
            chord: previewChord,
            pattern: pattern,
            preset: preset,
            patternStartBeat: 0.0,
            patternDurationBeats: patternDurationBeats,
            dynamics: .medium,
            midiChannel: midiChannel
        )
        
        return sequence
    }

    private func createNotesForPattern(chord: Chord, pattern: GuitarPattern, preset: Preset, patternStartBeat: MusicTimeStamp, patternDurationBeats: MusicTimeStamp, dynamics: MeasureDynamics, baseVelocity: UInt8 = 100) -> [MusicNote] {
        var musicNotes: [MusicNote] = []
        
        let transpositionOffset = MusicTheory.KEY_CYCLE.firstIndex(of: preset.key) ?? 0
        let fretsForPlayback = Array(chord.frets.reversed())

        let singleStepDurationBeats = pattern.steps.isEmpty ? patternDurationBeats : (patternDurationBeats / Double(pattern.steps.count))

        for (stepIndex, step) in pattern.steps.enumerated() {
            if step.activeNotes.isEmpty { continue }

            let activeNotesInStep = step.activeNotes.compactMap { stringIndex -> (note: UInt8, stringIndex: Int)? in
                var finalFret: Int
                if let overrideFret = step.fretOverrides[stringIndex] {
                    finalFret = overrideFret
                } else {
                    guard stringIndex < fretsForPlayback.count else { return nil }
                    finalFret = fretsForPlayback[stringIndex]
                }
                guard finalFret >= 0 else { return nil }
                let noteValue = MusicTheory.standardGuitarTuning[stringIndex] + finalFret + transpositionOffset
                return (note: UInt8(noteValue), stringIndex: stringIndex)
            }

            guard !activeNotesInStep.isEmpty else { continue }

            let velocityWithDynamics = UInt8(max(1, min(127, Double(baseVelocity) * dynamics.velocityMultiplier)))
            let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocityWithDynamics, noteCount: activeNotesInStep.count)

            switch step.type {
            case .arpeggio, .strum:
                let sortedNotes = activeNotesInStep.sorted { $0.stringIndex > $1.stringIndex }
                let isStrum = step.type == .strum
                let strumDelayBeats = isStrum ? strumDelayInBeats(for: step.strumSpeed, bpm: preset.bpm) : (singleStepDurationBeats / Double(activeNotesInStep.count))
                let strumDirectionSortedNotes = isStrum ? (step.strumDirection == .down ? sortedNotes : sortedNotes.reversed()) : sortedNotes

                for (noteIndex, noteItem) in strumDirectionSortedNotes.enumerated() {
                    var calculatedDurationBeats = patternDurationBeats // Default duration
                    
                    // Look ahead for the precise duration
                    for futureIndex in (stepIndex + 1)..<pattern.steps.count {
                        let futureStep = pattern.steps[futureIndex]
                        if futureStep.type == .rest || futureStep.activeNotes.contains(noteItem.stringIndex) {
                            calculatedDurationBeats = (Double(futureIndex - stepIndex) * singleStepDurationBeats)
                            break
                        }
                    }
                    
                    let noteStartTimeBeat = patternStartBeat + (Double(stepIndex) * singleStepDurationBeats) + (Double(noteIndex) * strumDelayBeats)
                    let finalVelocity = isStrum ? adaptiveVelocity : velocityWithDynamics
                    
                    if calculatedDurationBeats > 0 {
                        let musicNote = MusicNote(startTime: noteStartTimeBeat, duration: calculatedDurationBeats, pitch: Int(noteItem.note), velocity: Int(finalVelocity), technique: nil)
                        musicNotes.append(musicNote)
                    }
                }
            case .rest:
                break
            }
        }
        return musicNotes
    }

    private func addPatternToTrack(_ track: MusicTrack, chord: Chord, pattern: GuitarPattern, preset: Preset, patternStartBeat: MusicTimeStamp, patternDurationBeats: MusicTimeStamp, dynamics: MeasureDynamics, baseVelocity: UInt8 = 100, midiChannel: UInt8) {
        let notes = createNotesForPattern(chord: chord, pattern: pattern, preset: preset, patternStartBeat: patternStartBeat, patternDurationBeats: patternDurationBeats, dynamics: dynamics, baseVelocity: baseVelocity)
        
        for note in notes {
            var noteMessage = MIDINoteMessage(channel: midiChannel, note: UInt8(note.pitch), velocity: UInt8(note.velocity), releaseVelocity: 0, duration: Float(note.duration))
            MusicTrackNewMIDINoteEvent(track, note.startTime, &noteMessage)
        }
    }
    
    // MARK: - Helper Methods
    
    private func strumDelayInBeats(for speed: StrumSpeed, bpm: Double) -> MusicTimeStamp {
        let secondsPerBeat = 60.0 / bpm
        let delayInSeconds: TimeInterval
        switch speed {
        case .fast: delayInSeconds = 0.01
        case .medium: delayInSeconds = 0.025
        case .slow: delayInSeconds = 0.05
        }
        return delayInSeconds / secondsPerBeat
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
