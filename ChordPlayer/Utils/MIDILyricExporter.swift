
import Foundation

// MIDI 文件导出器
class MIDILyricExporter {
    
    // MARK: - Public API
    
    /// 导出歌词轨道为 MIDI 文件数据
    /// - Parameters:
    ///   - track: 要导出的歌词轨道
    ///   - preset: 包含完整数据的 Preset 对象
    ///   - ticksPerBeat: 每拍的 tick 数量，MIDI 时间精度
    /// - Returns: 生成的 MIDI 文件数据，如果失败则返回 nil
    public static func export(preset: Preset, ticksPerBeat: Int) -> Data? {
        // 1. 收集所有音符事件
        let allItems = collectAllItems(from: preset, ticksPerBeat: ticksPerBeat)
        
        // 如果没有有效内容，则直接返回
        guard !allItems.isEmpty else { return nil }
        
        // 2. 将音符事件转换为 MIDI 事件
        let midiEvents = createMidiEvents(from: allItems, preset: preset, ticksPerBeat: ticksPerBeat)
        
        // 3. 构建 MIDI 轨道数据
        let trackData = buildMidiTrack(events: midiEvents)
        
        // 4. 构建完整的 MIDI 文件数据
        return buildMidiFile(trackData: trackData, ticksPerBeat: ticksPerBeat)
    }
    
    // MARK: - Data Collection
    
    private static func collectAllItems(from preset: Preset, ticksPerBeat: Int) -> [AbsoluteMelodicItem] {
        var absoluteItems: [AbsoluteMelodicItem] = []
        let nativeTicksPerBeat = 12.0
        let scaleFactor = Double(ticksPerBeat) / nativeTicksPerBeat
        
        // 遍历所有歌词轨道
        for track in preset.arrangement.lyricsTracks {
            // 遍历轨道中的所有片段
            for segment in track.lyrics {
                // 确保片段包含有效文本且关联了旋律片段
                guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let melodicSegmentId = segment.melodicLyricSegmentId,
                      let melodicSegment = preset.melodicLyricSegments.first(where: { $0.id == melodicSegmentId }) else {
                    continue
                }
                
                for item in melodicSegment.items {
                    // 缩放内部 tick 到 MIDI 的 tick
                    let scaledPositionInTicks = Int(Double(item.positionInTicks) * scaleFactor)
                    let scaledDurationInTicks = item.durationInTicks.map { Int(Double($0) * scaleFactor) }

                    // 计算绝对 tick 位置
                    let absoluteStartTick = Int(segment.startBeat * Double(ticksPerBeat)) + scaledPositionInTicks
                    absoluteItems.append(AbsoluteMelodicItem(item: item, absoluteStartTick: absoluteStartTick, scaledDurationInTicks: scaledDurationInTicks))
                }
            }
        }
        
        // 按开始时间排序
        return absoluteItems.sorted { $0.absoluteStartTick < $1.absoluteStartTick }
    }
    
    // MARK: - MIDI Event Creation
    
    private static func createMidiEvents(from items: [AbsoluteMelodicItem], preset: Preset, ticksPerBeat: Int) -> [MIDIEvent] {
        var midiEvents: [MIDIEvent] = []
        let keySignature = KeySignature(key: preset.key)
        
        for item in items {
            // 跳过休止符或没有时长的音符
            guard item.item.pitch != 0, let duration = item.scaledDurationInTicks, duration > 0 else {
                continue
            }
            
            let midiNote = jianpuToMidiNote(
                pitch: item.item.pitch,
                octave: item.item.octave,
                pitchOffset: item.item.pitchOffset,
                keySignature: keySignature
            )
            
            // 歌词事件
            if !item.item.word.isEmpty {
                midiEvents.append(MIDIEvent(tick: item.absoluteStartTick, type: .lyric(item.item.word)))
            }
            
            // Note On 事件
            midiEvents.append(MIDIEvent(tick: item.absoluteStartTick, type: .noteOn(channel: 0, note: midiNote, velocity: 100)))
            
            // Note Off 事件
            let endTick = item.absoluteStartTick + duration
            midiEvents.append(MIDIEvent(tick: endTick, type: .noteOff(channel: 0, note: midiNote, velocity: 0)))
        }
        
        // 再次排序以确保所有事件（包括 Note Off）都按时间顺序排列
        return midiEvents.sorted { $0.tick < $1.tick }
    }
    
    // MARK: - MIDI File Construction
    
    private static func buildMidiTrack(events: [MIDIEvent]) -> Data {
        var trackData = Data()
        var lastTick: Int = 0
        
        for event in events {
            let deltaTick = event.tick - lastTick
            trackData.append(variableLengthQuantity(from: deltaTick))
            
            switch event.type {
            case .lyric(let text):
                trackData.append(0xFF) // Meta event
                trackData.append(0x05) // Lyric event
                let textData = text.data(using: .utf8) ?? Data()
                trackData.append(variableLengthQuantity(from: textData.count))
                trackData.append(textData)
                
            case .noteOn(let channel, let note, let velocity):
                trackData.append(0x90 | (UInt8(channel) & 0x0F))
                trackData.append(UInt8(note))
                trackData.append(UInt8(velocity))
                
            case .noteOff(let channel, let note, let velocity):
                trackData.append(0x80 | (UInt8(channel) & 0x0F))
                trackData.append(UInt8(note))
                trackData.append(UInt8(velocity))
            }
            
            lastTick = event.tick
        }
        
        // End of Track event
        trackData.append(Data([0x00, 0xFF, 0x2F, 0x00]))
        
        return trackData
    }
    
    private static func buildMidiFile(trackData: Data, ticksPerBeat: Int) -> Data {
        var fileData = Data()
        
        // Header Chunk (MThd)
        fileData.append("MThd".data(using: .ascii)!)
        fileData.append(uint32ToBytes(6)) // Chunk length
        fileData.append(uint16ToBytes(0)) // Format 0 (single track)
        fileData.append(uint16ToBytes(1)) // Number of tracks
        fileData.append(uint16ToBytes(UInt16(ticksPerBeat))) // Ticks per beat
        
        // Track Chunk (MTrk)
        fileData.append("MTrk".data(using: .ascii)!)
        fileData.append(uint32ToBytes(UInt32(trackData.count))) // Track length
        fileData.append(trackData)
        
        return fileData
    }
    
    // MARK: - Helpers
    
    /// 简谱到 MIDI 音高转换
    private static func jianpuToMidiNote(pitch: Int, octave: Int, pitchOffset: Int?, keySignature: KeySignature) -> UInt8 {
        let baseNote = keySignature.baseMidiNote
        let scaleIntervals = [0, 2, 4, 5, 7, 9, 11] // 大调音阶间隔
        
        guard pitch >= 1 && pitch <= 7 else { return 0 }
        
        let noteInOctave = baseNote + scaleIntervals[pitch - 1]
        let finalNote = noteInOctave + (octave * 12) + (pitchOffset ?? 0)
        
        return UInt8(clamping: finalNote)
    }
    
    /// 整数到可变长度量 (VLQ) 的转换
    private static func variableLengthQuantity(from value: Int) -> Data {
        var result = Data()
        var val = UInt32(value)
        var buffer: [UInt8] = []
        
        repeat {
            var byte = UInt8(val & 0x7F)
            val >>= 7
            if !buffer.isEmpty {
                byte |= 0x80
            }
            buffer.insert(byte, at: 0)
        } while val > 0
        
        if buffer.isEmpty {
            buffer.append(0)
        } else {
            for i in 0..<(buffer.count - 1) {
                buffer[i] |= 0x80
            }
        }
        
        result.append(contentsOf: buffer)
        return result
    }
    
    private static func uint32ToBytes(_ value: UInt32) -> Data {
        var val = value.bigEndian
        return Data(bytes: &val, count: MemoryLayout<UInt32>.size)
    }
    
    private static func uint16ToBytes(_ value: UInt16) -> Data {
        var val = value.bigEndian
        return Data(bytes: &val, count: MemoryLayout<UInt16>.size)
    }
}

// MARK: - Helper Structs

/// 包含绝对时间戳的旋律项
private struct AbsoluteMelodicItem {
    let item: MelodicLyricItem
    let absoluteStartTick: Int
    let scaledDurationInTicks: Int?
}

/// MIDI 事件的内部表示
private struct MIDIEvent {
    let tick: Int
    let type: MIDIEventType
}

private enum MIDIEventType {
    case lyric(String)
    case noteOn(channel: Int, note: UInt8, velocity: UInt8)
    case noteOff(channel: Int, note: UInt8, velocity: UInt8)
}

/// 调性结构，用于计算音高
private struct KeySignature {
    let key: String
    
    // C4 (Middle C) is MIDI note 60
    var baseMidiNote: Int {
        switch key.uppercased() {
        case "C": return 60
        case "G": return 67
        case "D": return 62
        case "A": return 69
        case "E": return 64
        case "B": return 71
        case "F#", "GB": return 66
        case "C#", "DB": return 61
        case "G#", "AB": return 68
        case "D#", "EB": return 63
        case "A#", "BB": return 70
        case "F": return 65
        default: return 60 // Default to C
        }
    }
}
