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
}