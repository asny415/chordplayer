import Foundation
import Combine
import AudioToolbox

class DrumPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    private var appData: AppData

    // MARK: - Playback State
    @Published var isPlaying: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        
        // Subscribe to the central sequencer's state
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            if self?.isPlaying != sequencerIsPlaying {
                self?.isPlaying = sequencerIsPlaying
            }
        }.store(in: &cancellables)
    }

    /// Plays a single drum pattern for a couple of loops for preview purposes.
    func preview(pattern: DrumPattern) {
        let singlePatternBeats = Double(pattern.length) / (pattern.resolution == .sixteenth ? 4.0 : 2.0)
        let previewDuration = singlePatternBeats * 2.0 // Preview for 2 loops

        guard let sequence = createSequence(from: pattern, loopDurationInBeats: previewDuration),
              let endpoint = midiManager.selectedOutput else {
            print("[DrumPlayer] Failed to create preview sequence.")
            return
        }
        midiSequencer.play(sequence: sequence, on: endpoint)
    }

    func playNote(midiNote: Int) {
        let channel = UInt8(appData.drumMidiChannel - 1)
        midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100, channel: channel)
        // Schedule a note-off event shortly after, without using the sequencer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 0, channel: channel)
        }
    }

    /// Stops any playback handled by the central sequencer.
    func stop() {
        if isPlaying {
            midiSequencer.stop()
        }
    }

    /// Creates a MusicSequence for a given drum pattern, looped for a specified duration.
    /// This is the core method to be called by PresetArrangerPlayer.
    /// - Parameters:
    ///   - pattern: The `DrumPattern` to sequence.
    ///   - loopDurationInBeats: The total duration in beats the pattern should fill.
    /// - Returns: A `MusicSequence` containing the looped drum track, or `nil` on failure.
    func createSequence(from pattern: DrumPattern, loopDurationInBeats: Double) -> MusicSequence? {
        guard let preset = appData.preset else { return nil }

        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }

        // Set tempo on the tempo track
        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        // Create a track for the drum events
        var drumTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &drumTrack)
        guard status == noErr, let track = drumTrack else { return nil }

        let stepsPerBeat = pattern.resolution == .sixteenth ? 4.0 : 2.0
        let singlePatternDurationBeats = Double(pattern.length) / stepsPerBeat
        
        guard singlePatternDurationBeats > 0 else { return nil }

        let repeatCount = Int(ceil(loopDurationInBeats / singlePatternDurationBeats))
        let noteDuration: Float = 0.1 // Short duration for drum hits

        for i in 0..<repeatCount {
            let beatOffset = Double(i) * singlePatternDurationBeats

            for stepIndex in 0..<pattern.length {
                let noteBeat = beatOffset + (Double(stepIndex) / stepsPerBeat)
                
                // Ensure notes are not scheduled beyond the total required duration
                guard noteBeat < loopDurationInBeats else { continue }

                for instrumentIndex in 0..<pattern.instruments.count {
                    if pattern.patternGrid[instrumentIndex][stepIndex] {
                        let midiNote = UInt8(pattern.midiNotes[instrumentIndex])
                        let velocity = UInt8(100) // Default velocity
                        
                        var noteMessage = MIDINoteMessage(
                            channel: UInt8(appData.drumMidiChannel - 1),
                            note: midiNote,
                            velocity: velocity,
                            releaseVelocity: 0,
                            duration: noteDuration
                        )
                        MusicTrackNewMIDINoteEvent(track, noteBeat, &noteMessage)
                    }
                }
            }
        }
        
        return sequence
    }
}