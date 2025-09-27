
import Foundation
import AudioToolbox

public enum MIDIDebugger {
    public static func describe(sequence: MusicSequence) -> String {
        var description = "Music Sequence Description:\n"
        
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)
        description += "  Track count: \(trackCount)\n"
        
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            
            guard let currentTrack = track else {
                description += "  Track \(i): Could not be retrieved\n"
                continue
            }
            
            description += "  ------------------------\n"
            description += "  Track \(i):\n"
            
            var iterator: MusicEventIterator?
            NewMusicEventIterator(currentTrack, &iterator)
            
            guard let eventIterator = iterator else {
                description += "    Could not create event iterator for this track.\n"
                continue
            }
            
            var hasNextEvent: DarwinBoolean = false
            MusicEventIteratorHasNextEvent(eventIterator, &hasNextEvent)
            
            while hasNextEvent.boolValue {
                var timestamp: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer? = nil
                var eventDataSize: UInt32 = 0
                
                MusicEventIteratorGetEventInfo(eventIterator, &timestamp, &eventType, &eventData, &eventDataSize)
                
                var eventDescription = "    - Event at time \(String(format: "%.2f", timestamp)):"                
                switch eventType {
                case kMusicEventType_MIDINoteMessage:
                    if let data = eventData {
                        let noteMessage = data.assumingMemoryBound(to: MIDINoteMessage.self).pointee
                        eventDescription += " Note On: note=\(noteMessage.note), velocity=\(noteMessage.velocity), duration=\(noteMessage.duration)"
                    }
                case kMusicEventType_MIDIChannelMessage:
                    if let data = eventData {
                        let channelMessage = data.assumingMemoryBound(to: MIDIChannelMessage.self).pointee
                        eventDescription += " Channel Msg: status=\(String(format: "%02X", channelMessage.status)), data1=\(channelMessage.data1), data2=\(channelMessage.data2)"
                    }
                case kMusicEventType_Meta:
                     if let data = eventData {
                        let metaEvent = data.assumingMemoryBound(to: MIDIMetaEvent.self).pointee
                        eventDescription += " Meta Event: type=\(metaEvent.metaEventType), byteCount=\(metaEvent.dataLength)"
                    }
                case kMusicEventType_ExtendedTempo:
                    if let data = eventData {
                        let tempoEvent = data.assumingMemoryBound(to: ExtendedTempoEvent.self).pointee
                        eventDescription += " Tempo Event: bpm=\(tempoEvent.bpm)"
                    }
                default:
                    eventDescription += " Other Event: type=\(eventType)"
                }
                
                description += eventDescription + "\n"
                
                MusicEventIteratorNextEvent(eventIterator)
                MusicEventIteratorHasNextEvent(eventIterator, &hasNextEvent)
            }
            
            DisposeMusicEventIterator(eventIterator)
        }
        
        return description
    }
}
