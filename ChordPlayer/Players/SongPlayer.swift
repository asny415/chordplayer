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

        // 从头开始播放
        midiSequencer.seek(to: 0.0)

        guard let masterSong = createMasterSong(for: preset),
              let endpoint = midiManager.selectedOutput else {
            print("[PresetArrangerPlayer] Failed to create master song or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(song: masterSong, on: endpoint)
    }
    
    func playFromCurrentPosition() {
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
        
        // 获取当前播放位置
        let currentPosition = midiSequencer.currentTimeInBeats
        
        // 播放歌曲
        midiSequencer.play(song: masterSong, on: endpoint)
        
        // 跳转到当前位置
        midiSequencer.seek(to: currentPosition)
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
                guard let pattern = appData.getDrumPattern(for: segment.patternId) else {
                    continue
                }
                let channel = UInt8((preset.arrangement.drumTrack.midiChannel ?? 10) - 1)
                guard let drumSong = drumPlayer.createSong(from: pattern, loopDurationInBeats: segment.durationInBeats, onChannel: channel) else {
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
                 // Try to find melodic data using the new reference field first (for new arrangements with repeated segments)
                 // If that's nil, try the old method for backward compatibility
                 var melodicData: MelodicLyricSegment?
                 if let melodicLyricSegmentId = segment.melodicLyricSegmentId {
                     // New method: use the explicit reference
                     melodicData = preset.melodicLyricSegments.first(where: { $0.id == melodicLyricSegmentId })
                 } else {
                     // Old method: direct ID match (for backward compatibility with old saved data)
                     melodicData = preset.melodicLyricSegments.first(where: { $0.id == segment.id })
                 }
                 
                 if let melodicData = melodicData {
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
}