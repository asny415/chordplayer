import Foundation
import Combine
import AudioToolbox
import CoreMIDI

class PresetArrangerPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    private var appData: AppData
    private var chordPlayer: ChordPlayer
    private var drumPlayer: DrumPlayer
    private var soloPlayer: SoloPlayer
    private var melodicLyricPlayer: MelodicLyricPlayer

    // MARK: - Published State (Mirrors MIDISequencer)
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0.0 // In beats
    
    private var cancellables = Set<AnyCancellable>()

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData, chordPlayer: ChordPlayer, drumPlayer: DrumPlayer, soloPlayer: SoloPlayer, melodicLyricPlayer: MelodicLyricPlayer) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        self.chordPlayer = chordPlayer
        self.drumPlayer = drumPlayer
        self.soloPlayer = soloPlayer
        self.melodicLyricPlayer = melodicLyricPlayer

        // Bind state to the central sequencer
        self.midiSequencer.$isPlaying
            .assign(to: &$isPlaying)
        
        self.midiSequencer.$currentTimeInBeats
            .assign(to: &$playbackPosition)
    }

    // MARK: - Public Playback Controls

    func play() {
        guard let preset = appData.preset else { return }
        
        if isPlaying {
            stop()
            return
        }

        guard let masterSong = createMasterSong(for: preset),
              let endpoint = midiManager.selectedOutput else {
            print("[PresetArrangerPlayer] Failed to create master song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: masterSong, on: endpoint)
    }

    func stop() {
        midiSequencer.stop()
    }
    
    func pause() {
        midiSequencer.pause()
    }

    func resume() {
        if let endpoint = midiManager.selectedOutput {
            midiSequencer.resume(on: endpoint)
        }
    }

    func seekTo(beat: Double) {
        midiSequencer.seek(to: beat)
    }

    // MARK: - Master Song Creation (New)

    private func createMasterSong(for preset: Preset) -> MusicSong? {
        var masterSong = MusicSong(
            tempo: preset.bpm,
            key: preset.key,
            timeSignature: .init(numerator: preset.timeSignature.beatsPerMeasure, denominator: preset.timeSignature.beatUnit),
            tracks: []
        )

        // 1. Drum Track
        if !preset.arrangement.drumTrack.isMuted {
            for segment in preset.arrangement.drumTrack.segments {
                guard let pattern = appData.getDrumPattern(for: segment.patternId),
                      let drumSong = drumPlayer.createSong(from: pattern, loopDurationInBeats: segment.durationInBeats) else {
                    continue
                }
                masterSong.merge(with: drumSong, at: segment.startBeat)
            }
        }
        
        // 2. Guitar Tracks (Solo & Accompaniment)
        for guitarTrack in preset.arrangement.guitarTracks where !guitarTrack.isMuted {
            for segment in guitarTrack.segments {
                let channel = UInt8((guitarTrack.midiChannel ?? appData.chordMidiChannel) - 1)
                // Set pitch bend range for this channel before creating the song
                midiManager.setPitchBendRange(channel: channel)
                
                var segmentSong: MusicSong?
                
                switch segment.type {
                case .solo(let segmentId):
                    if let soloData = appData.getSoloSegment(for: segmentId) {
                        segmentSong = soloPlayer.createSong(from: soloData, onChannel: channel)
                    }
                case .accompaniment(let segmentId):
                    if let accompData = appData.getAccompanimentSegment(for: segmentId) {
                        segmentSong = chordPlayer.createSong(from: accompData, onChannel: channel)
                    }
                }
                
                if let song = segmentSong {
                    masterSong.merge(with: song, at: segment.startBeat)
                }
            }
        }
        
        // 3. Lyrics Tracks (Melody)
        for lyricsTrack in preset.arrangement.lyricsTracks where !lyricsTrack.isMuted {
            for segment in lyricsTrack.lyrics {
                 if let melodicData = preset.melodicLyricSegments.first(where: { $0.id == segment.id }) {
                    let channel = UInt8((lyricsTrack.midiChannel ?? 4) - 1) // Default to channel 4
                    // Set pitch bend range for this channel before creating the song
                    midiManager.setPitchBendRange(channel: channel)

                    if let lyricSong = melodicLyricPlayer.createSong(from: melodicData, onChannel: channel) {
                        masterSong.merge(with: lyricSong, at: segment.startBeat)
                    }
                 }
            }
        }

        return masterSong
    }

    // MARK: - Master Sequence Creation (Legacy)

    private func createMasterSequence(for preset: Preset) -> MusicSequence? {
        var masterSequence: MusicSequence?
        var status = NewMusicSequence(&masterSequence)
        guard status == noErr, let sequence = masterSequence else { return nil }

        // Set tempo
        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        // --- Assemble Tracks ---
        
        // 1. Drum Track
        if !preset.arrangement.drumTrack.isMuted {
            for segment in preset.arrangement.drumTrack.segments {
                guard let pattern = appData.getDrumPattern(for: segment.patternId),
                      let drumSequence = drumPlayer.createSequence(from: pattern, loopDurationInBeats: segment.durationInBeats) else {
                    continue
                }
                merge(sequence: drumSequence, into: sequence, at: segment.startBeat)
            }
        }
        
        // 2. Guitar Tracks (Solo & Accompaniment)
        for guitarTrack in preset.arrangement.guitarTracks where !guitarTrack.isMuted {
            for segment in guitarTrack.segments {
                let channel = UInt8((guitarTrack.midiChannel ?? appData.chordMidiChannel) - 1)
                var segmentSequence: MusicSequence?
                
                switch segment.type {
                case .solo(let segmentId):
                    if let soloData = appData.getSoloSegment(for: segmentId) {
                        segmentSequence = soloPlayer.createSequence(from: soloData, onChannel: channel)
                    }
                case .accompaniment(let segmentId):
                    if let accompData = appData.getAccompanimentSegment(for: segmentId) {
                        segmentSequence = chordPlayer.createSequence(from: accompData, onChannel: channel)
                    }
                }
                
                if let seq = segmentSequence {
                    merge(sequence: seq, into: sequence, at: segment.startBeat)
                }
            }
        }
        
        // 3. Lyrics Tracks (Melody)
        for lyricsTrack in preset.arrangement.lyricsTracks where !lyricsTrack.isMuted {
            for segment in lyricsTrack.lyrics {
                 if let melodicData = preset.melodicLyricSegments.first(where: { $0.id == segment.id }) {
                    let channel = UInt8((lyricsTrack.midiChannel ?? 4) - 1) // Default to channel 4
                    if let lyricSequence = melodicLyricPlayer.createSequence(from: melodicData, onChannel: channel) {
                        merge(sequence: lyricSequence, into: sequence, at: segment.startBeat)
                    }
                 }
            }
        }

        return sequence
    }
    
    /// Merges all tracks from a source sequence into a destination sequence, offsetting by a start beat.
    private func merge(sequence source: MusicSequence, into destination: MusicSequence, at startBeat: MusicTimeStamp) {
        var sourceTrackCount: UInt32 = 0
        MusicSequenceGetTrackCount(source, &sourceTrackCount)

        for i in 0..<sourceTrackCount {
            var sourceTrack: MusicTrack?
            guard MusicSequenceGetIndTrack(source, i, &sourceTrack) == noErr, let sourceTrack = sourceTrack else { continue }
            
            // Get track length to determine if it's empty
            var trackLength: MusicTimeStamp = 0
            var propertySize = UInt32(MemoryLayout<MusicTimeStamp>.size)
            guard MusicTrackGetProperty(sourceTrack, kSequenceTrackProperty_TrackLength, &trackLength, &propertySize) == noErr else { continue }

            // Don't merge empty tracks
            if trackLength > 0 {
                var destinationTrack: MusicTrack?
                MusicSequenceNewTrack(destination, &destinationTrack)
                
                if let destinationTrack = destinationTrack {
                    MusicTrackCopyInsert(sourceTrack, 0, trackLength, destinationTrack, startBeat)
                }
            }
        }
    }
}
