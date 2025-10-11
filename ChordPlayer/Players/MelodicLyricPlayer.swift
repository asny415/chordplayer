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

    func play(segment: MelodicLyricSegment, midiChannel: UInt8) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stop()
            return
        }
        
        stop() // Stop any previous playback

        guard let song = createSong(from: segment, onChannel: midiChannel),
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
        var consumedItemIDs = Set<UUID>()
        let transposition = self.transposition(forKey: preset.key)
        let ticksPerBeat = 12.0 // Use a double for division
        let segmentEndBeat = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        for i in 0..<itemsSorted.count {
            let currentItem = itemsSorted[i]
            if consumedItemIDs.contains(currentItem.id) || currentItem.pitch == 0 { continue }
            
            guard let pitch1 = midiNote(for: currentItem, transposition: transposition) else { continue }

            let startTime = Double(currentItem.positionInTicks) / ticksPerBeat
            var duration: Double
            var technique: MusicPlayingTechnique? = nil

            // Slide has a special duration calculation, so we handle it separately.
            if currentItem.technique == .slide, let targetItem = itemsSorted.dropFirst(i + 1).first(where: { $0.pitch > 0 && !consumedItemIDs.contains($0.id) }) {
                
                consumedItemIDs.insert(targetItem.id)
                let slideTransitionDuration = Double(targetItem.positionInTicks - currentItem.positionInTicks) / ticksPerBeat
                duration = slideTransitionDuration > 0 ? slideTransitionDuration : 0
                
                if let targetPitch = midiNote(for: targetItem, transposition: transposition) {
                    let durationAtTarget = Double(targetItem.durationInTicks ?? 3) / ticksPerBeat
                    technique = .slide(toPitch: Int(targetPitch), durationAtTarget: durationAtTarget)
                }

            } else {
                // For all other notes, calculate duration first, then process techniques.
                
                // 1. Calculate duration based on the *next immediate* note.
                if let durationTicks = currentItem.durationInTicks {
                    duration = Double(durationTicks) / ticksPerBeat
                } else {
                    let nextItemStartTime = itemsSorted.dropFirst(i + 1).first?.positionInTicks
                    let nextNoteStartBeat = nextItemStartTime.map { Double($0) / ticksPerBeat }
                    duration = (nextNoteStartBeat ?? segmentEndBeat) - startTime
                }

                // 2. Process techniques and consume notes.
                switch currentItem.technique {
                case .bend:
                    if i + 2 < itemsSorted.count {
                        let item2 = itemsSorted[i+1]
                        let item3 = itemsSorted[i+2]
                        if let pitch2 = midiNote(for: item2, transposition: transposition),
                           let pitch3 = midiNote(for: item3, transposition: transposition),
                           !consumedItemIDs.contains(item2.id), !consumedItemIDs.contains(item3.id),
                           pitch2 > pitch1 && pitch3 == pitch1 {

                            consumedItemIDs.insert(item2.id)
                            consumedItemIDs.insert(item3.id)

                            let releaseDuration = Double(item2.durationInTicks ?? 3) / ticksPerBeat
                            let sustainDuration = Double(item3.durationInTicks ?? 3) / ticksPerBeat
                            technique = .bend(targetPitch: Int(pitch2), releaseDuration: releaseDuration, sustainDuration: sustainDuration)
                        } 
                    }
                case .vibrato:
                    technique = .vibrato
                case .pullOff:
                    technique = .pullOff
                default:
                    technique = nil
                }
            }
            
            if duration > 0 {
                let velocity = (currentItem.technique == .pullOff) ? 50 : 100
                let musicNote = MusicNote(startTime: startTime, duration: duration, pitch: Int(pitch1), velocity: velocity, technique: technique)
                musicNotes.append(musicNote)
            }
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
        let finalMidiNote = baseMidiNote + scaleOffset + octaveOffset + (item.pitchOffset ?? 0)
        return UInt8(finalMidiNote)
    }
}