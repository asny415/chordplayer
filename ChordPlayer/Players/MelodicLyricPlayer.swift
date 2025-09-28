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
        midiManager.setPitchBendRange(channel: channel)

        guard let song = createSong(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[MelodicLyricPlayer] Failed to create song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: song, on: endpoint)
        
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func createSong(from segment: MelodicLyricSegment, onChannel midiChannel: UInt8) -> MusicSong? {
        guard let preset = appData.preset else { return nil }
        
        var musicNotes: [MusicNote] = []
        let itemsSorted = segment.items.sorted { $0.position < $1.position }
        var consumedItemIDs = Set<UUID>()
        let transposition = self.transposition(forKey: preset.key)
        let sixteenthNote = 0.25
        let segmentEndBeat = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        for i in 0..<itemsSorted.count {
            let currentItem = itemsSorted[i]
            if consumedItemIDs.contains(currentItem.id) || currentItem.pitch == 0 { continue }

            let startTime = Double(currentItem.position) * sixteenthNote
            var duration: Double
            var technique: MusicPlayingTechnique? = nil

            // Default duration calculation
            let noteOffBeat: Double
            if let duration16ths = currentItem.duration {
                noteOffBeat = Double(currentItem.position + duration16ths) * sixteenthNote
            } else {
                let nextNoteStartBeat = itemsSorted.dropFirst(i + 1).first(where: { $0.pitch > 0 })
                    .map { Double($0.position) * sixteenthNote }
                noteOffBeat = nextNoteStartBeat ?? segmentEndBeat
            }
            duration = noteOffBeat - startTime

            // Technique handling
            if currentItem.technique == .slide, let targetItem = itemsSorted.dropFirst(i + 1).first(where: { $0.pitch > 0 && !consumedItemIDs.contains($0.id) }) {
                consumedItemIDs.insert(targetItem.id)
                
                guard let targetPitch = midiNote(for: targetItem, transposition: transposition) else { continue }
                
                let slideTransitionDuration = (Double(targetItem.position) * sixteenthNote) - startTime
                
                // Calculate target item's duration in beats
                let targetNoteOffBeat: Double
                if let targetDuration16ths = targetItem.duration {
                    targetNoteOffBeat = Double(targetItem.position + targetDuration16ths) * sixteenthNote
                } else {
                    let nextTargetNoteStartBeat = itemsSorted.dropFirst(i + 2).first(where: { $0.pitch > 0 })
                        .map { Double($0.position) * sixteenthNote }
                    targetNoteOffBeat = nextTargetNoteStartBeat ?? segmentEndBeat
                }
                let durationAtTarget = targetNoteOffBeat - (Double(targetItem.position) * sixteenthNote)

                duration = slideTransitionDuration
                technique = .slide(toPitch: Int(targetPitch), durationAtTarget: durationAtTarget)

            } else if currentItem.technique == .bend {
                technique = .bend(amount: 2.0)
            } else if currentItem.technique == .vibrato {
                technique = .vibrato
            } else if currentItem.technique == .pullOff {
                technique = .pullOff
            }

            guard duration > 0, let pitch = midiNote(for: currentItem, transposition: transposition) else { continue }
            
            let velocity = (currentItem.technique == .pullOff) ? 50 : 100
            let musicNote = MusicNote(startTime: startTime, duration: duration, pitch: Int(pitch), velocity: velocity, technique: technique)
            musicNotes.append(musicNote)
        }

        let track = SongTrack(instrumentName: "Melody", midiChannel: Int(midiChannel), notes: musicNotes)
        let song = MusicSong(tempo: preset.bpm, key: preset.key, timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit), tracks: [track])
        return song
    }


    func stop() {
        midiSequencer.stop()
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
        }
    }
    
    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        return keyMap[key] ?? 0
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
}
