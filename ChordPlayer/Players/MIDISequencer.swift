import Foundation
import AudioToolbox
import CoreMIDI

/**
 `MIDISequencer` 是一个现代化的MIDI序列播放引擎，负责高精度、高性能地播放 `MusicSequence` 对象。
 
 它封装了Apple的 `MusicPlayer` API，并将播放状态作为 `ObservableObject` 发布，以便于和SwiftUI视图集成。
 这个类的设计遵循单一职责原则，只关心序列的播放控制，而不处理MIDI设备的管理或实时消息的发送。
 */
class MIDISequencer: ObservableObject {
    
    // MARK: - Published Properties
    
    /// `true` 表示当前正在播放。
    @Published var isPlaying: Bool = false
    
    /// 播放头当前所在的节拍位置。
    @Published var currentTimeInBeats: MusicTimeStamp = 0.0
    
    // MARK: - Private Properties
    
    /// 底层的Core Audio播放器实例。
    private var musicPlayer: MusicPlayer?
    
    /// 当前加载到播放器中的序列。
    private var currentSequence: MusicSequence?
    
    /// 用于实现暂停/继续功能，记录暂停时的节拍位置。
    private var pauseTime: MusicTimeStamp? = nil
    
    /// 对MidiManager的弱引用，用于发送实时消息（如panic）。
    private weak var midiManager: MidiManager?
    
    // MARK: - Initialization
    
    init(midiManager: MidiManager) {
        self.midiManager = midiManager
        
        var player: MusicPlayer?
        let status = NewMusicPlayer(&player)
        if status == noErr {
            self.musicPlayer = player
        } else {
            print("Error creating MusicPlayer: \(status). See CoreMIDI error codes.")
        }
    }
    
    deinit {
        if let player = self.musicPlayer {
            MusicPlayerStop(player)
            DisposeMusicPlayer(player)
        }
        if let sequence = self.currentSequence {
            DisposeMusicSequence(sequence)
        }
    }
    
    // MARK: - Public API
    
    /// 播放一个新的MusicSequence。
    /// - Parameters:
    ///   - sequence: 要播放的音乐数据对象。
    ///   - endpoint: 目标MIDI输出设备。
    func play(sequence: MusicSequence, on endpoint: MIDIEndpointRef) {
        guard let player = self.musicPlayer else { return }
        
        if isPlaying {
            stop()
        }
        
        // 释放旧的序列
        if let oldSequence = self.currentSequence {
            DisposeMusicSequence(oldSequence)
        }
        self.currentSequence = sequence
        
        // 关键：将序列的MIDI事件路由到指定的endpoint
        MusicSequenceSetMIDIEndpoint(sequence, endpoint)
        
        // 将新序列加载到播放器
        MusicPlayerSetSequence(player, sequence)
        
        // 重置暂停时间并从头开始播放
        self.pauseTime = nil
        MusicPlayerStart(player)
        self.isPlaying = true
    }
    
    /// 完全停止播放，并将播放头重置到序列的开头。
    func stop() {
        guard let player = self.musicPlayer, isPlaying else { return }
        
        MusicPlayerStop(player)
        
        // 发送 all-notes-off 消息来防止音符粘连
        midiManager?.sendPanic()
        
        self.isPlaying = false
        self.pauseTime = nil
        self.currentTimeInBeats = 0.0
    }
    
    /// 暂停播放，保持当前播放头的位置。
    func pause() {
        guard let player = self.musicPlayer, isPlaying else { return }
        
        // 记录暂停位置
        var tempPauseTime: MusicTimeStamp = 0.0
        MusicPlayerGetTime(player, &tempPauseTime)
        self.pauseTime = tempPauseTime
        self.currentTimeInBeats = tempPauseTime
        
        MusicPlayerStop(player)
        self.isPlaying = false
    }
    
    /// 从上次暂停的位置继续播放。
    /// - Parameter endpoint: 目标MIDI输出设备，以防在暂停期间设备发生变化。
    func resume(on endpoint: MIDIEndpointRef) {
        guard let player = self.musicPlayer, !isPlaying, let resumeTime = self.pauseTime else { return }
        guard let sequence = self.currentSequence else { return }
        
        // 重新确认endpoint
        MusicSequenceSetMIDIEndpoint(sequence, endpoint)
        
        // 恢复播放位置
        MusicPlayerSetTime(player, resumeTime)
        
        MusicPlayerStart(player)
        self.isPlaying = true
        self.pauseTime = nil
    }
    
    /// 将播放头即时移动到指定的节拍（beat）位置。
    /// - Parameter beats: 目标节拍位置。
    func seek(to beats: MusicTimeStamp) {
        guard let player = self.musicPlayer else { return }
        
        MusicPlayerSetTime(player, beats)
        self.currentTimeInBeats = beats
        
        // 如果是暂停状态，更新暂停时间，以便从新位置继续
        if !isPlaying && self.pauseTime != nil {
            self.pauseTime = beats
        }
    }
}
