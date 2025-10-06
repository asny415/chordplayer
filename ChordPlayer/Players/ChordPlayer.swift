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
        guard let song = createSongForPattern(pattern, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[ChordPlayer] Failed to create preview song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: song, on: endpoint)
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

        let patternDurationBeats = Double(pattern.length) * (pattern.activeResolution == .sixteenth ? 0.25 : 0.5)
        
        let notes = createNotesForPattern(
            chord: chord,
            pattern: pattern,
            preset: preset,
            patternStartBeat: 0.0,
            patternDurationBeats: patternDurationBeats,
            dynamics: .medium
        )
        
        let track = SongTrack(instrumentName: "Single Play", midiChannel: Int(channel), notes: notes)
        let song = MusicSong(tempo: preset.bpm, key: preset.key, timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit), tracks: [track])

        guard let endpoint = midiManager.selectedOutput else {
            print("[ChordPlayer] Failed to get MIDI endpoint for single play.")
            return
        }
        midiSequencer.play(song: song, on: endpoint)
    }

    // MARK: - Song Creation

    func createSong(from segment: AccompanimentSegment, onChannel midiChannel: UInt8) -> MusicSong? {
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
    
    func createSongForPattern(_ pattern: GuitarPattern, onChannel midiChannel: UInt8) -> MusicSong? {
        guard let preset = appData.preset else { return nil }
        
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        let patternDurationBeats = Double(pattern.length) * (pattern.activeResolution == .sixteenth ? 0.25 : 0.5)

        let notes = createNotesForPattern(
            chord: previewChord,
            pattern: pattern,
            preset: preset,
            patternStartBeat: 0.0,
            patternDurationBeats: patternDurationBeats,
            dynamics: .medium
        )
        
        let track = SongTrack(instrumentName: "Pattern Preview", midiChannel: Int(midiChannel), notes: notes)
        let song = MusicSong(tempo: preset.bpm, key: preset.key, timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit), tracks: [track])
        return song
    }

    private func createNotesForPattern(chord: Chord, pattern: GuitarPattern, preset: Preset, patternStartBeat: MusicTimeStamp, patternDurationBeats: MusicTimeStamp, dynamics: MeasureDynamics, baseVelocity: UInt8 = 100) -> [MusicNote] {
        
        struct TemporalNote: Comparable {
            let stringIndex: Int
            let startTime: Double
            var duration: Double
            let pitch: Int
            let velocity: Int
            let technique: PlayingTechnique?

            static func < (lhs: TemporalNote, rhs: TemporalNote) -> Bool {
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                return lhs.stringIndex < rhs.stringIndex
            }
        }

        var temporalNotes: [TemporalNote] = []
        let transpositionOffset = MusicTheory.KEY_CYCLE.firstIndex(of: preset.key) ?? 0
        let fretsForPlayback = Array(chord.frets.reversed())
        let singleStepDurationBeats = pattern.steps.isEmpty ? 0 : (patternDurationBeats / Double(pattern.steps.count))

        // 1. Flatten pattern into a temporal list of notes
        for (stepIndex, step) in pattern.steps.enumerated() {
            if step.type == .rest || step.activeNotes.isEmpty { continue }

            let activeNotesInStep = step.activeNotes.compactMap { stringIndex -> (note: UInt8, stringIndex: Int)? in
                let finalFret = step.fretOverrides[stringIndex] ?? (stringIndex < fretsForPlayback.count ? fretsForPlayback[stringIndex] : -1)
                guard finalFret >= 0 else { return nil }
                let noteValue = MusicTheory.standardGuitarTuning[stringIndex] + finalFret + transpositionOffset
                return (note: UInt8(noteValue), stringIndex: stringIndex)
            }

            guard !activeNotesInStep.isEmpty else { continue }

            let velocityWithDynamics = UInt8(max(1, min(127, Double(baseVelocity) * dynamics.velocityMultiplier)))
            let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocityWithDynamics, noteCount: activeNotesInStep.count)
            
            let sortedNotes = activeNotesInStep.sorted { $0.stringIndex > $1.stringIndex }
            let isStrum = step.type == .strum
            let strumDelayBeats = isStrum ? strumDelayInBeats(for: step.strumSpeed, bpm: preset.bpm) : (singleStepDurationBeats / Double(activeNotesInStep.count))
            let strumDirectionSortedNotes = isStrum ? (step.strumDirection == .down ? sortedNotes : sortedNotes.reversed()) : sortedNotes

            for (noteIndex, noteItem) in strumDirectionSortedNotes.enumerated() {
                let noteStartTimeBeat = patternStartBeat + (Double(stepIndex) * singleStepDurationBeats) + (Double(noteIndex) * strumDelayBeats)
                let finalVelocity = isStrum ? adaptiveVelocity : velocityWithDynamics
                let technique = step.techniques[noteItem.stringIndex]

                let temporalNote = TemporalNote(stringIndex: noteItem.stringIndex, startTime: noteStartTimeBeat, duration: 0, pitch: Int(noteItem.note), velocity: Int(finalVelocity), technique: technique)
                temporalNotes.append(temporalNote)
            }
        }
        
        guard !temporalNotes.isEmpty else { return [] }
        
        temporalNotes.sort()

        // Calculate precise durations
        for i in 0..<temporalNotes.count {
            let currentNote = temporalNotes[i]
            var calculatedDuration: Double
            
            // Find the next note on the same string
            let nextNoteOnSameString = temporalNotes.dropFirst(i + 1).first { $0.stringIndex == currentNote.stringIndex }
            
            if let nextNote = nextNoteOnSameString {
                calculatedDuration = nextNote.startTime - currentNote.startTime
            } else {
                // If no next note, it plays until the end of the pattern
                calculatedDuration = (patternStartBeat + patternDurationBeats) - currentNote.startTime
            }
            temporalNotes[i].duration = calculatedDuration
        }

        // 2. Process techniques with look-ahead
        var musicNotes: [MusicNote] = []
        var consumedIndexes = Set<Int>()

        for i in 0..<temporalNotes.count {
            if consumedIndexes.contains(i) { continue }
            
            let currentNote = temporalNotes[i]
            var musicTechnique: MusicPlayingTechnique? = nil

            switch currentNote.technique {
            case .slide:
                if let nextNoteIndex = temporalNotes.dropFirst(i + 1).firstIndex(where: { $0.stringIndex == currentNote.stringIndex }) {
                    let nextNote = temporalNotes[nextNoteIndex]
                    consumedIndexes.insert(nextNoteIndex)
                    musicTechnique = .slide(toPitch: nextNote.pitch, durationAtTarget: nextNote.duration)
                }

            case .bend:
                let subsequentNotes = temporalNotes.dropFirst(i + 1).filter { $0.stringIndex == currentNote.stringIndex }
                if subsequentNotes.count >= 2 {
                    let noteB = subsequentNotes[subsequentNotes.startIndex]
                    let noteC = subsequentNotes[subsequentNotes.startIndex + 1]
                    
                    if let noteBIndex = temporalNotes.firstIndex(where: { $0.startTime == noteB.startTime && $0.pitch == noteB.pitch }),
                       let noteCIndex = temporalNotes.firstIndex(where: { $0.startTime == noteC.startTime && $0.pitch == noteC.pitch }) {
                        
                        if noteB.pitch > currentNote.pitch && noteC.pitch == currentNote.pitch {
                            consumedIndexes.insert(noteBIndex)
                            consumedIndexes.insert(noteCIndex)
                            musicTechnique = .bend(targetPitch: noteB.pitch, releaseDuration: noteB.duration, sustainDuration: noteC.duration)
                        }
                    }
                }
                
            default:
                musicTechnique = nil
            }
            
            if currentNote.duration > 0 {
                let finalNote = MusicNote(startTime: currentNote.startTime, duration: currentNote.duration, pitch: currentNote.pitch, velocity: currentNote.velocity, technique: musicTechnique)
                musicNotes.append(finalNote)
            }
        }
        
        return musicNotes
    }

    // MARK: - Legacy Sequence Creation (to be removed)
    func createSequence(from segment: AccompanimentSegment, onChannel midiChannel: UInt8) -> MusicSequence? {
        return nil // No longer implemented
    }
    
    private func addPatternToTrack(_ track: MusicTrack, chord: Chord, pattern: GuitarPattern, preset: Preset, patternStartBeat: MusicTimeStamp, patternDurationBeats: MusicTimeStamp, dynamics: MeasureDynamics, baseVelocity: UInt8 = 100, midiChannel: UInt8) {
        // No longer implemented
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
