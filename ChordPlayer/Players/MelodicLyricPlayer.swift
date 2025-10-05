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
        
        let itemsSorted = segment.items.sorted { $0.positionInTicks < $1.positionInTicks }
        var musicNotes: [MusicNote] = []
        let transposition = self.transposition(forKey: preset.key)
        let ticksPerBeat = 12.0 // Use a double for division
        let segmentEndBeat = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        var i = 0
        while i < itemsSorted.count {
            let item1 = itemsSorted[i]
            
            guard item1.pitch > 0, let pitch1 = midiNote(for: item1, transposition: transposition) else {
                i += 1
                continue
            }

            var technique: MusicPlayingTechnique? = nil
            var shouldIncrementByOne = true
            let startTime = Double(item1.positionInTicks) / ticksPerBeat

            switch item1.technique {
            case .bend:
                if i + 2 < itemsSorted.count {
                    let item2 = itemsSorted[i+1]
                    let item3 = itemsSorted[i+2]

                    if let pitch2 = midiNote(for: item2, transposition: transposition),
                       let pitch3 = midiNote(for: item3, transposition: transposition),
                       pitch2 > pitch1 && pitch3 == pitch1 {

                        let releaseDuration = Double(item2.durationInTicks ?? 3) / ticksPerBeat
                        let sustainDuration = Double(item3.durationInTicks ?? 3) / ticksPerBeat
                        let initialDuration = Double(item1.durationInTicks ?? 3) / ticksPerBeat

                        technique = .bend(targetPitch: Int(pitch2), releaseDuration: releaseDuration, sustainDuration: sustainDuration)
                        
                        let musicNote = MusicNote(startTime: startTime, duration: initialDuration, pitch: Int(pitch1), velocity: 100, technique: technique)
                        musicNotes.append(musicNote)
                        
                        i += 3
                        shouldIncrementByOne = false
                        
                    } else {
                        technique = nil // Validation failed
                    }
                } else {
                    technique = nil // Not enough notes
                }

            case .slide:
                 if let item2 = itemsSorted.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                    if let pitch2 = midiNote(for: item2, transposition: transposition) {
                        let durationAtTarget = Double(item2.durationInTicks ?? 3) / ticksPerBeat
                        technique = .slide(toPitch: Int(pitch2), durationAtTarget: durationAtTarget)
                    }
                }

            case .vibrato:
                technique = .vibrato
            case .pullOff:
                technique = .pullOff
            case .normal, .none:
                technique = nil
            }

            if shouldIncrementByOne {
                let duration: Double
                if let durationTicks = item1.durationInTicks {
                    duration = Double(durationTicks) / ticksPerBeat
                } else {
                    let nextNoteStartBeat = itemsSorted.dropFirst(i + 1).first(where: { $0.pitch > 0 })
                        .map { Double($0.positionInTicks) / ticksPerBeat }
                    duration = (nextNoteStartBeat ?? segmentEndBeat) - startTime
                }
                
                if duration > 0 {
                    let velocity = (item1.technique == .pullOff) ? 50 : 100
                    let musicNote = MusicNote(startTime: startTime, duration: duration, pitch: Int(pitch1), velocity: velocity, technique: technique)
                    musicNotes.append(musicNote)
                }
                i += 1
            }
        }

        let track = SongTrack(instrumentName: "Melody", midiChannel: Int(midiChannel), notes: musicNotes)
        let song = MusicSong(tempo: preset.bpm, key: preset.key, timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit), tracks: [track])
        
        if let json = song.dumpJSON() {
            print("--- Generated MusicSong for MelodicLyricPlayer ---")
            print(json)
            print("----------------------------------------------------")
        }

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
