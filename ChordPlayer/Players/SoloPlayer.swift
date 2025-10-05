import Foundation
import Combine
import AudioToolbox

class SoloPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    var appData: AppData

    // MARK: - Playback State
    @Published var isPlaying: Bool = false
    private var currentlyPlayingSegmentID: UUID?
    private var cancellables = Set<AnyCancellable>()

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(note: SoloNote, offTime: Double)
        case bend(from: SoloNote, to: SoloNote, offTime: Double)
    }
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        print("[SoloPlayer] Initialized.")
        
        // Subscribe to sequencer's isPlaying state
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            print("[SoloPlayer] Sink received: midiSequencer.isPlaying is now \(sequencerIsPlaying)")
            if !sequencerIsPlaying {
                self?.isPlaying = false
                self?.currentlyPlayingSegmentID = nil
                print("[SoloPlayer] Sink updated self.isPlaying to false.")
            }
        }.store(in: &cancellables)
    }

    func play(segment: SoloSegment, channel: UInt8 = 0) {
        print("[SoloPlayer] play() called with new MusicSong interface.")
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            print("[SoloPlayer] play() -> stopping existing playback.")
            stop()
            return
        }
        
        stop() // Stop any previous playback

        midiManager.setPitchBendRange(channel: channel)

        guard let song = createSong(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("Failed to create song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: song, on: endpoint)
        
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func stop() {
        print("[SoloPlayer] stop() called.")
        midiSequencer.stop()
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
            print("[SoloPlayer] stop() updated self.isPlaying to false.")
        }
    }
    
    func createSong(from segment: SoloSegment, onChannel midiChannel: UInt8) -> MusicSong? {
        guard let preset = appData.preset else { return nil }

        let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
        let transposition = self.transposition(forKey: preset.key)
        var musicNotes: [MusicNote] = []
        
        var i = 0
        while i < notesSortedByTime.count {
            let note1 = notesSortedByTime[i]
            
            // Skip invalid or already processed notes
            guard note1.fret >= 0 else {
                i += 1
                continue
            }

            let pitch1 = midiNote(from: note1.string, fret: note1.fret, transposition: transposition)
            var technique: MusicPlayingTechnique? = nil
            var shouldIncrementByOne = true

            switch note1.technique {
            case .bend:
                // Check for the 3-note bend sequence
                if i + 2 < notesSortedByTime.count {
                    let note2 = notesSortedByTime[i+1]
                    let note3 = notesSortedByTime[i+2]
                    
                    let pitch2 = midiNote(from: note2.string, fret: note2.fret, transposition: transposition)
                    let pitch3 = midiNote(from: note3.string, fret: note3.fret, transposition: transposition)

                    // Validation for the bend sequence
                    if note1.string == note2.string && note2.string == note3.string &&
                       pitch2 > pitch1 && pitch3 == pitch1 {
                        
                        let releaseDuration = note2.duration ?? 0.25 // Default duration if nil
                        let sustainDuration = note3.duration ?? 0.25 // Default duration if nil
                        
                        technique = .bend(targetPitch: Int(pitch2), releaseDuration: releaseDuration, sustainDuration: sustainDuration)
                        
                        let musicNote = MusicNote(startTime: note1.startTime,
                                                  duration: note1.duration ?? 0.25,
                                                  pitch: Int(pitch1),
                                                  velocity: 100,
                                                  technique: technique)
                        musicNotes.append(musicNote)
                        
                        i += 3 // Consume all 3 notes
                        shouldIncrementByOne = false
                        
                    } else {
                        // Validation failed, treat as a normal note
                        technique = nil
                    }
                } else {
                    // Not enough notes for a bend, treat as normal
                    technique = nil
                }

            case .slide:
                if let note2 = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == note1.string }) {
                    let pitch2 = midiNote(from: note2.string, fret: note2.fret, transposition: transposition)
                    technique = .slide(toPitch: Int(pitch2), durationAtTarget: note2.duration ?? 1.0)
                    // This is tricky with a while loop. For now, we don't consume the slide target.
                    // The sequencer should handle this by looking at the technique.
                } else {
                    technique = nil // Slide to nowhere, treat as normal
                }
            
            case .vibrato:
                technique = .vibrato
            case .pullOff:
                technique = .pullOff
            case .normal:
                technique = nil
            }
            
            if shouldIncrementByOne {
                let velocity = (note1.technique == .pullOff) ? 50 : 100
                let musicNote = MusicNote(startTime: note1.startTime,
                                          duration: note1.duration ?? 1.0,
                                          pitch: Int(pitch1),
                                          velocity: velocity,
                                          technique: technique)
                musicNotes.append(musicNote)
                i += 1
            }
        }

        let soloTrack = SongTrack(instrumentName: "Solo Guitar",
                                  midiChannel: Int(midiChannel),
                                  notes: musicNotes)
        
        let song = MusicSong(tempo: appData.preset?.bpm ?? 120.0,
                             key: appData.preset?.key ?? "C",
                             timeSignature: MusicTimeSignature(numerator: 4, denominator: 4),
                             tracks: [soloTrack])
        
        return song
    }

    private func midiNote(from string: Int, fret: Int, transposition: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        let baseNote = openStringMIDINotes[string] + UInt8(fret)
        return baseNote + UInt8(transposition)
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