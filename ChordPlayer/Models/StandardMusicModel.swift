import Foundation

// MARK: - 顶层结构

public struct MusicSong: Codable {
    /// 歌曲的速度 (BPM)
    public var tempo: Double
    
    /// 歌曲的调
    public var key: String
    
    /// 拍号
    public var timeSignature: MusicTimeSignature
    
    /// 乐器轨道
    public var tracks: [SongTrack]
}

public struct MusicTimeSignature: Codable {
    /// 分子
    public var numerator: Int
    
    /// 分母
    public var denominator: Int
}

public struct SongTrack: Codable {
    /// 轨道名称
    public var instrumentName: String
    
    /// MIDI通道
    public var midiChannel: Int
    
    /// 轨道中的音符数组
    public var notes: [MusicNote]
}


// MARK: - 核心定义

/**
 * 代表一个音乐事件或音符。
 * 这是模型的核心，描述了音符本身和它的演奏方式。
 */
public struct MusicNote: Codable {
    /// 音符的起始时间，以“节拍”为单位。
    public var startTime: Double
    
    /// 音符的总持续时间，以“节拍”为单位。
    public var duration: Double
    
    /// 音符的起始音高 (MIDI 0-127)。
    public var pitch: Int
    
    /// MIDI力度 (0-127)。
    public var velocity: Int
    
    /// 演奏技巧。如果没有值(nil)，则表示这是一个普通的音符。
    public var technique: MusicPlayingTechnique?
}

/**
 * 定义了支持的演奏技巧及其所需的最简参数。
 */
public enum MusicPlayingTechnique: Codable {
    case hammerOn
    case pullOff
    case vibrato
    case bend(amount: Double)
    case slide(toPitch: Int, durationAtTarget: Double)
}

// MARK: - JSON Dump Utility

extension MusicSong {
    /// Dumps the contents of the MusicSong instance into a pretty-printed JSON string.
    /// - Returns: A formatted JSON string, or nil if encoding fails.
    public func dumpJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error encoding MusicSong to JSON: \(error)")
            return nil
        }
    }
}