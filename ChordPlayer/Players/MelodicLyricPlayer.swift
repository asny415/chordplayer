import Foundation
import Combine
import AudioToolbox

class MelodicLyricPlayer: ObservableObject {
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
        
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            if !sequencerIsPlaying {
                self?.isPlaying = false
                self?.currentlyPlayingSegmentID = nil
            }
        }.store(in: &cancellables)
    }

    func play(segment: MelodicLyricSegment) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stop()
            return
        }
        
        stop()

        // TODO: Add a dedicated MIDI channel for melody in AppData
        let channel: UInt8 = 3 
        midiManager.setPitchBendRange(channel: channel, rangeInSemitones: 2)

        guard let sequence = createSequence(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[MelodicLyricPlayer] Failed to create sequence or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(sequence: sequence, on: endpoint)
        
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func stop() {
        midiSequencer.stop()
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
        }
    }
    
    private func createSequence(from segment: MelodicLyricSegment, onChannel midiChannel: UInt8) -> MusicSequence? {
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

        enum MusicalAction {
            case playNote(item: MelodicLyricItem, offTimeInBeats: Double)
            // TODO: Add back slide, bend, vibrato actions
        }

        let transposition = self.transposition(forKey: preset.key)
        let sixteenthNoteDurationInBeats = 0.25
        let segmentDurationInBeats = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        let itemsSortedByTime = segment.items.sorted { $0.position < $1.position }
        var actions: [MusicalAction] = []

        for i in 0..<itemsSortedByTime.count {
            let currentItem = itemsSortedByTime[i]
            if currentItem.pitch == 0 { continue } // Skip rests

            let noteOffBeat: Double
            if let duration = currentItem.duration {
                noteOffBeat = Double(currentItem.position + duration) * sixteenthNoteDurationInBeats
            } else {
                var endPositionIn16th = segmentDurationInBeats / sixteenthNoteDurationInBeats
                if let nextItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                    endPositionIn16th = Double(nextItem.position)
                }
                noteOffBeat = endPositionIn16th * sixteenthNoteDurationInBeats
            }

            // For now, all techniques are simplified to playNote
            actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
        }
        
        for action in actions {
            let velocity = UInt8(100) // Default velocity

            switch action {
            case .playNote(let item, let offTimeInBeats):
                guard let midiNoteNumber = midiNote(for: item, transposition: transposition) else { continue }
                let noteOnBeat = Double(item.position) * sixteenthNoteDurationInBeats
                let durationBeats = offTimeInBeats - noteOnBeat
                
                if durationBeats > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: midiNoteNumber, velocity: velocity, releaseVelocity: 0, duration: Float(durationBeats))
                    MusicTrackNewMIDINoteEvent(track, noteOnBeat, &noteMessage)
                }
            }
        }
        
        return sequence
    }

    private func midiNote(for item: MelodicLyricItem, transposition: Int) -> UInt8? {
        let scaleOffsets: [Int: Int] = [
            1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11 // Major scale intervals
        ]
        guard item.pitch > 0, let scaleOffset = scaleOffsets[item.pitch] else { return nil }
        
        let baseMidiNote = 60 + transposition // C4 + key transposition
        let octaveOffset = item.octave * 12
        return UInt8(baseMidiNote + scaleOffset + octaveOffset)
    }
    
    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        return keyMap[key] ?? 0
    }
}
