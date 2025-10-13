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

        let capoValue = appData.preset?.capo ?? 0
        guard let song = createSong(from: segment, onChannel: channel, capo: capoValue),
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
    
    func createSong(from segment: SoloSegment, onChannel midiChannel: UInt8, capo: Int) -> MusicSong? {
        guard let preset = appData.preset else { return nil }

        // Use the passed-in capo value directly
        let capoValue = capo
        
        let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
        var consumedNoteIDs = Set<UUID>()
        var musicNotes: [MusicNote] = []

        for i in 0..<notesSortedByTime.count {
            let currentNote = notesSortedByTime[i]
            if consumedNoteIDs.contains(currentNote.id) || currentNote.fret < 0 { continue }

            var duration = currentNote.duration ?? 1.0
            let pitch = midiNote(from: currentNote.string, fret: currentNote.fret + capoValue) // Apply capo offset
            var technique: MusicPlayingTechnique? = nil

            switch currentNote.technique {
            case .slide:
                if let targetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string && !consumedNoteIDs.contains($0.id) }) {
                    consumedNoteIDs.insert(targetNote.id)
                    
                    // Correctly calculate slide transition duration
                    let slideTransitionDuration = targetNote.startTime - currentNote.startTime
                    if slideTransitionDuration > 0 {
                        duration = slideTransitionDuration
                    }

                    let targetPitch = midiNote(from: targetNote.string, fret: targetNote.fret + capoValue) // Apply capo offset
                    let durationAtTarget = targetNote.duration ?? 1.0
                    technique = .slide(toPitch: Int(targetPitch), durationAtTarget: durationAtTarget)
                } else {
                    technique = nil // Slide to nowhere, treat as normal
                }
            case .bend:
                if i + 2 < notesSortedByTime.count {
                    let note2 = notesSortedByTime[i+1]
                    let note3 = notesSortedByTime[i+2]
                    let pitch2 = midiNote(from: note2.string, fret: note2.fret + capoValue) // Apply capo offset
                    let pitch3 = midiNote(from: note3.string, fret: note3.fret + capoValue) // Apply capo offset

                    if !consumedNoteIDs.contains(note2.id) && !consumedNoteIDs.contains(note3.id) &&
                       currentNote.string == note2.string && note2.string == note3.string &&
                       pitch2 > pitch && pitch3 == pitch {
                        
                        consumedNoteIDs.insert(note2.id)
                        consumedNoteIDs.insert(note3.id)
                        
                        let releaseDuration = note2.duration ?? 0.25
                        let sustainDuration = note3.duration ?? 0.25
                        technique = .bend(targetPitch: Int(pitch2), releaseDuration: releaseDuration, sustainDuration: sustainDuration)
                        
                    } else {
                        technique = nil // Validation failed
                    }
                } else {
                    technique = nil // Not enough notes
                }
            case .vibrato:
                technique = .vibrato
            case .pullOff:
                technique = .pullOff
            case .normal:
                technique = nil
            }
            
            guard duration > 0 else { continue }
            let velocity = (currentNote.technique == .pullOff) ? 50 : 100

            let musicNote = MusicNote(startTime: currentNote.startTime,
                                      duration: duration,
                                      pitch: Int(pitch),
                                      velocity: velocity,
                                      technique: technique)
            musicNotes.append(musicNote)
        }

        let soloTrack = SongTrack(instrumentName: "Solo Guitar",
                                  midiChannel: Int(midiChannel),
                                  notes: musicNotes)
        
        let song = MusicSong(tempo: appData.preset?.bpm ?? 120.0,
                             key: appData.preset?.key ?? "C",
                             timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit),
                             tracks: [soloTrack])
        
        return song
    }

    private func midiNote(from string: Int, fret: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        let baseNote = openStringMIDINotes[string] + UInt8(fret)
        return baseNote
    }


}