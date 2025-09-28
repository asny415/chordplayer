import Foundation
import AudioToolbox
import CoreMIDI

class MIDISequencer: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isPlaying: Bool = false
    @Published var currentTimeInBeats: MusicTimeStamp = 0.0
    
    // MARK: - Private Properties
    private var musicPlayer: MusicPlayer?
    private var currentSequence: MusicSequence?
    private var currentSequenceLength: MusicTimeStamp = 0.0
    private var pauseTime: MusicTimeStamp? = nil
    private var statusTimer: Timer?
    private weak var midiManager: MidiManager?
    
    // MARK: - Initialization
    init(midiManager: MidiManager) {
        self.midiManager = midiManager
        var player: MusicPlayer?
        let status = NewMusicPlayer(&player)
        if status == noErr {
            self.musicPlayer = player
        } else {
            print("Error creating MusicPlayer: \(status).")
        }
    }
    
    deinit {
        stopTimer()
        if let player = self.musicPlayer {
            MusicPlayerStop(player)
            DisposeMusicPlayer(player)
        }
        if let sequence = self.currentSequence {
            DisposeMusicSequence(sequence)
        }
    }
    
    // MARK: - Public API
    func play(sequence: MusicSequence, on endpoint: MIDIEndpointRef) {
        guard let player = self.musicPlayer else { return }
        
        if isPlaying {
            stop()
        }
        
        if let oldSequence = self.currentSequence {
            DisposeMusicSequence(oldSequence)
        }
        self.currentSequence = sequence
        
        // Get and store sequence length by finding the max track length
        self.currentSequenceLength = 0.0
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        print("[MIDISequencer] Sequence has \(trackCount) tracks.")
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            if let track = track {
                var trackLength: MusicTimeStamp = 0
                var propertySize = UInt32(MemoryLayout<MusicTimeStamp>.size)
                let status = MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &trackLength, &propertySize)
                if status == noErr {
                    print("[MIDISequencer] Track \(i) length: \(trackLength)")
                    if trackLength > self.currentSequenceLength {
                        self.currentSequenceLength = trackLength
                    }
                } else {
                    print("[MIDISequencer] Could not get length for track \(i). Status: \(status)")
                }
            }
        }
        print("[MIDISequencer] Final sequence length: \(self.currentSequenceLength) beats.")

        MusicSequenceSetMIDIEndpoint(sequence, endpoint)
        MusicPlayerSetSequence(player, sequence)
        
        self.pauseTime = nil
        MusicPlayerStart(player)
        self.isPlaying = true
        
        startTimer()
    }
    
    func stop() {
        guard let player = self.musicPlayer else { return }
        guard isPlaying else { return }
        
        MusicPlayerStop(player)
        midiManager?.sendPanic()
        
        DispatchQueue.main.async {
            if self.isPlaying { // Double-check state before modifying
                self.isPlaying = false
                self.pauseTime = nil
                self.currentTimeInBeats = 0.0
                self.stopTimer()
                print("[MIDISequencer] stop() executed. isPlaying is now false.")
            }
        }
    }
    
    func pause() {
        guard let player = self.musicPlayer, isPlaying else { return }
        
        var tempPauseTime: MusicTimeStamp = 0.0
        MusicPlayerGetTime(player, &tempPauseTime)
        
        MusicPlayerStop(player)

        DispatchQueue.main.async {
            self.pauseTime = tempPauseTime
            self.currentTimeInBeats = tempPauseTime
            self.isPlaying = false
            self.stopTimer()
        }
    }
    
    func resume(on endpoint: MIDIEndpointRef) {
        guard let player = self.musicPlayer, !isPlaying, let resumeTime = self.pauseTime else { return }
        guard let sequence = self.currentSequence else { return }
        
        MusicSequenceSetMIDIEndpoint(sequence, endpoint)
        MusicPlayerSetTime(player, resumeTime)
        
        MusicPlayerStart(player)
        self.isPlaying = true
        self.pauseTime = nil
        startTimer()
    }
    
    func seek(to beats: MusicTimeStamp) {
        guard let player = self.musicPlayer else { return }
        
        MusicPlayerSetTime(player, beats)
        DispatchQueue.main.async {
            self.currentTimeInBeats = beats
            if !self.isPlaying && self.pauseTime != nil {
                self.pauseTime = beats
            }
        }
    }
    
    // MARK: - Timer and Status Update
    
    private func startTimer() {
        stopTimer()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updatePlaybackStatus()
        }
    }
    
    private func stopTimer() {
        statusTimer?.invalidate()
        statusTimer = nil
    }
    
    @objc private func updatePlaybackStatus() {
        guard let player = self.musicPlayer, isPlaying else { return }
        
        var isPlayerRunning: DarwinBoolean = false
        MusicPlayerIsPlaying(player, &isPlayerRunning)
        
        var currentTime: MusicTimeStamp = 0
        MusicPlayerGetTime(player, &currentTime)
        
        DispatchQueue.main.async {
            self.currentTimeInBeats = currentTime
            
            // Check for natural finish
            let finishedNaturally = !isPlayerRunning.boolValue || (self.currentSequenceLength > 0 && currentTime >= self.currentSequenceLength)
            
            if finishedNaturally {
                print("Playback finished naturally. Player running: \(isPlayerRunning.boolValue), Time: \(currentTime)/\(self.currentSequenceLength)")
                self.stop()
            }
        }
    }

    // MARK: - Song Model Playback
    
    public func play(song: MusicSong, on endpoint: MIDIEndpointRef) {
        if let json = song.dumpJSON() {
            print("--- Playing MusicSong ---")
            print(json)
            print("-----------------------")
        }

        guard let sequence = createMusicSequence(from: song) else {
            print("Failed to create MusicSequence from Song object.")
            return
        }
        play(sequence: sequence, on: endpoint)
    }
    
    private func createMusicSequence(from song: MusicSong) -> MusicSequence? {
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }
        
        // Set Tempo
        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, song.tempo)
        }
        
        for songTrackModel in song.tracks {
            var musicTrack: MusicTrack? // This is the AudioToolbox.MusicTrack
            status = MusicSequenceNewTrack(sequence, &musicTrack)
            guard status == noErr, let track = musicTrack else { continue }
            
            // Process notes
            for noteModel in songTrackModel.notes {
                addNote(noteModel, to: track, channel: UInt8(songTrackModel.midiChannel))
            }
        }
        
        return sequence
    }

    private func addNote(_ note: MusicNote, to track: MusicTrack, channel: UInt8) {
        // Add the basic note on/off event
        var noteMessage = MIDINoteMessage(channel: channel,
                                          note: UInt8(note.pitch),
                                          velocity: UInt8(note.velocity),
                                          releaseVelocity: 0,
                                          duration: Float32(note.duration))
        
        MusicTrackNewMIDINoteEvent(track, note.startTime, &noteMessage)
        
        // Handle techniques
        switch note.technique {
        case .bend(let amount):
            let bendValue = UInt16(8192 + (amount / 2.0) * 4096) // Assuming a +/- 2 semitone range
            addPitchBendEvent(to: track, at: note.startTime, value: 8192, channel: channel) // Reset bend
            addPitchBendEvent(to: track, at: note.startTime + 0.01, value: bendValue, channel: channel) // Apply bend
            addPitchBendEvent(to: track, at: note.startTime + note.duration, value: 8192, channel: channel) // Reset at end

        case .slide(let toPitch, let durationAtTarget):
            let pitchDifference = toPitch - note.pitch
            let slideDuration = note.duration - durationAtTarget
            
            if slideDuration > 0 {
                let bendValue = UInt16(8192 + (Double(pitchDifference) / 2.0) * 4096) // Assuming +/- 2 semitone range
                addPitchBendEvent(to: track, at: note.startTime, value: 8192, channel: channel) // Reset bend
                addPitchBendEvent(to: track, at: note.startTime + slideDuration, value: bendValue, channel: channel) // Apply slide
                addPitchBendEvent(to: track, at: note.startTime + note.duration, value: bendValue, channel: channel) // Keep bend until end
            }

        case .vibrato, .hammerOn, .pullOff, .none:
            break
        }
    }
    
    private func addPitchBendEvent(to track: MusicTrack, at time: MusicTimeStamp, value: UInt16, channel: UInt8) {
        let lsb = UInt8(value & 0x7F)
        let msb = UInt8((value >> 7) & 0x7F)
        var pitchBendMessage = MIDIChannelMessage(status: 0xE0 | channel, data1: lsb, data2: msb, reserved: 0)
        MusicTrackNewMIDIChannelEvent(track, time, &pitchBendMessage)
    }
}
