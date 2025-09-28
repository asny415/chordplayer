import Foundation
import Combine
import AudioToolbox

class MelodicLyricPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    var appData: AppData

    // MARK: - Playback State
    @Published var isPlaying: Bool = false
    private var currentlyPlayingSegmentID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            if !sequencerIsPlaying {
                self?.isPlaying = false
                self?.currentlyPlayingSegmentID = nil
            }
        }.store(in: &cancellables)
    }

    func play(segment: MelodicLyricSegment) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stop()
            return
        }
        
        stop()

        // TODO: Add a dedicated MIDI channel for melody in AppData
        let channel: UInt8 = 3 
        midiManager.setPitchBendRange(channel: channel)

        guard let sequence = createSequence(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("[MelodicLyricPlayer] Failed to create sequence or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(sequence: sequence, on: endpoint)
        
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func stop() {
        midiSequencer.stop()
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
        }
    }
    
    func createSequence(from segment: MelodicLyricSegment, onChannel midiChannel: UInt8) -> MusicSequence? {
        guard let preset = appData.preset else { return nil }
        
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }

        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, preset.bpm)
        }

        var musicTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &musicTrack)
        guard status == noErr, let track = musicTrack else { return nil }

        enum MusicalAction {
            case playNote(item: MelodicLyricItem, offTimeInBeats: Double)
            case slide(from: MelodicLyricItem, to: MelodicLyricItem, offTimeInBeats: Double)
            case vibrato(item: MelodicLyricItem, offTimeInBeats: Double)
            case bend(from: MelodicLyricItem, to: MelodicLyricItem, offTimeInBeats: Double)
        }

        let transposition = self.transposition(forKey: preset.key)
        let sixteenthNoteDurationInBeats = 0.25
        let segmentDurationInBeats = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        let itemsSortedByTime = segment.items.sorted { $0.position < $1.position }
        var actions: [MusicalAction] = []

        var consumedItemIDs = Set<UUID>() // Track items that are consumed as part of compound actions
        
        for i in 0..<itemsSortedByTime.count {
            let currentItem = itemsSortedByTime[i]
            if currentItem.pitch == 0 || consumedItemIDs.contains(currentItem.id) { continue } // Skip rests and consumed items

            let noteOffBeat: Double
            if let duration = currentItem.duration {
                noteOffBeat = Double(currentItem.position + duration) * sixteenthNoteDurationInBeats
            } else {
                var endPositionIn16th = segmentDurationInBeats / sixteenthNoteDurationInBeats
                if let nextItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                    endPositionIn16th = Double(nextItem.position)
                }
                noteOffBeat = endPositionIn16th * sixteenthNoteDurationInBeats
            }

            // Handle techniques
            if let technique = currentItem.technique {
                switch technique {
                case .slide:
                    // Look for the next item on the same "string" (we'll define this as the same pitch range for melody)
                    if let nextItem = itemsSortedByTime.dropFirst(i + 1).first(where: { item in
                        item.pitch > 0 && !consumedItemIDs.contains(item.id)
                    }) {
                        consumedItemIDs.insert(nextItem.id)
                        let slideOffTime = noteOffBeat // Use the original off time
                        actions.append(.slide(from: currentItem, to: nextItem, offTimeInBeats: slideOffTime))
                    } else {
                        actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
                    }
                case .bend:
                    if let nextItem = itemsSortedByTime.dropFirst(i + 1).first(where: { item in
                        item.pitch > 0 && !consumedItemIDs.contains(item.id)
                    }) {
                        consumedItemIDs.insert(nextItem.id)
                        let bendOffTime = noteOffBeat
                        actions.append(.bend(from: currentItem, to: nextItem, offTimeInBeats: bendOffTime))
                    } else {
                        actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
                    }
                case .vibrato:
                    actions.append(.vibrato(item: currentItem, offTimeInBeats: noteOffBeat))
                case .pullOff:
                    // Pull-off is handled by velocity adjustment
                    actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
                case .normal:
                    actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
                }
            } else {
                actions.append(.playNote(item: currentItem, offTimeInBeats: noteOffBeat))
            }
        }
        
        for action in actions {
            // Determine velocity based on technique
            var baseVelocity = UInt8(100)
            
            var shouldUsePullOffVelocity = false
            switch action {
            case .playNote(let item, _):
                shouldUsePullOffVelocity = (item.technique == .pullOff)
            case .vibrato(let item, _):
                shouldUsePullOffVelocity = (item.technique == .pullOff)
            case .bend(let fromItem, _, _):
                shouldUsePullOffVelocity = (fromItem.technique == .pullOff)
            case .slide(let fromItem, _, _):
                shouldUsePullOffVelocity = (fromItem.technique == .pullOff)
            }
            
            let velocity = shouldUsePullOffVelocity ? UInt8(max(1, Int(baseVelocity) / 2)) : baseVelocity

            switch action {
            case .playNote(let item, let offTimeInBeats):
                guard let midiNoteNumber = midiNote(for: item, transposition: transposition) else { continue }
                let noteOnBeat = Double(item.position) * sixteenthNoteDurationInBeats
                let durationBeats = offTimeInBeats - noteOnBeat
                
                if durationBeats > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: midiNoteNumber, velocity: velocity, releaseVelocity: 0, duration: Float(durationBeats))
                    MusicTrackNewMIDINoteEvent(track, noteOnBeat, &noteMessage)
                }
                
            case .slide(let fromItem, let toItem, let offTimeInBeats):
                guard let startMidiNote = midiNote(for: fromItem, transposition: transposition),
                      let endMidiNote = midiNote(for: toItem, transposition: transposition) else { continue }
                      
                var semitoneDifference = Int(endMidiNote) - Int(startMidiNote)
                let pitchBendRangeSemitones = 2.0

                // 如果 semitoneDifference 大于 pitchBendRangeSemitones，则限制在范围内
                let clampedSemitoneDifference = max(-Int(pitchBendRangeSemitones), min(Int(pitchBendRangeSemitones), semitoneDifference))
                if semitoneDifference != clampedSemitoneDifference {
                    print("[MelodicLyricPlayer] Slide exceeds pitch bend range. Clamping from \(semitoneDifference) to \(clampedSemitoneDifference).")
                }

                let noteOnTime = Double(fromItem.position) * sixteenthNoteDurationInBeats
                let slideTargetTime = Double(toItem.position) * sixteenthNoteDurationInBeats
                var finalNoteOffTime = offTimeInBeats
                var needPlayToItem = false
                //如果 semitoneDifference == clampedSemitoneDifference，说明没有超出范围，正常滑音，将 toItem 的时长也算上
                if semitoneDifference == clampedSemitoneDifference {
                    // Extend the final note off time to include the toItem's duration
                    let toItemOffTime: Double
                    if let duration = toItem.duration {
                        toItemOffTime = Double(toItem.position + duration) * sixteenthNoteDurationInBeats
                    } else {
                        var endPositionIn16th = segmentDurationInBeats / sixteenthNoteDurationInBeats
                        if let nextItem = itemsSortedByTime.first(where: { $0.position > toItem.position && $0.pitch > 0 }) {
                            endPositionIn16th = Double(nextItem.position)
                        }
                        toItemOffTime = endPositionIn16th * sixteenthNoteDurationInBeats
                    }
                    // Use the later of the two off times
                    let extendedFinalOffTime = max(finalNoteOffTime, toItemOffTime)
                    // Update finalNoteOffTime
                    // Note: This won't affect the note duration calculation below since it's already been calculated
                    // But it will ensure the pitch bend reset happens after the full duration
                    finalNoteOffTime = extendedFinalOffTime
                } else {
                    // 如果超出弯音范围，需要正常演奏目标音符
                    needPlayToItem = true
                }

                semitoneDifference = clampedSemitoneDifference
                let noteDuration = finalNoteOffTime - noteOnTime

                // Pluck the first note
                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: startMidiNote, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(track, noteOnTime, &noteMessage)
                }

                // Add pitch bend events with delayed start
                let totalSlideDuration = slideTargetTime - noteOnTime
                let slideDelay = min(totalSlideDuration / 2.0, 0.25) // Half duration or quarter note (0.25), whichever is smaller
                let actualSlideStartTime = noteOnTime + slideDelay
                let actualSlideDuration = slideTargetTime - actualSlideStartTime
                
                if actualSlideDuration > 0.01 && abs(semitoneDifference) > 0 {
                    let pitchBendSteps = max(2, Int(actualSlideDuration * 50)) // 50 steps per beat
                    
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTime = actualSlideStartTime + t * actualSlideDuration
                        let finalPitchBendValue = 8192 + Int(Double(semitoneDifference) * (8191.0 / pitchBendRangeSemitones))
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        let clampedPitch = max(0, min(16383, intermediatePitch))
                        
                        var pitchBendMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(clampedPitch & 0x7F), data2: UInt8((clampedPitch >> 7) & 0x7F), reserved: 0)
                        MusicTrackNewMIDIChannelEvent(track, bendTime, &pitchBendMessage)
                    }
                }
                
                // Reset bend after the note is off
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(track, finalNoteOffTime - 0.01, &pitchBendResetMessage)

                if needPlayToItem {
                    // Pluck the target note if slide exceeded pitch bend range
                    let toItemOnTime = Double(toItem.position) * sixteenthNoteDurationInBeats
                    let toItemDuration: Double
                    if let duration = toItem.duration {
                        toItemDuration = Double(duration) * sixteenthNoteDurationInBeats
                    } else {
                        var endPositionIn16th = segmentDurationInBeats / sixteenthNoteDurationInBeats
                        if let nextItem = itemsSortedByTime.first(where: { $0.position > toItem.position && $0.pitch > 0 }) {
                            endPositionIn16th = Double(nextItem.position)
                        }
                        toItemDuration = (endPositionIn16th * sixteenthNoteDurationInBeats) - toItemOnTime
                    }
                    if toItemDuration > 0 {
                        var noteMessage = MIDINoteMessage(channel: midiChannel, note: endMidiNote, velocity: velocity, releaseVelocity: 0, duration: Float(toItemDuration))
                        MusicTrackNewMIDINoteEvent(track, toItemOnTime, &noteMessage)
                    }
                }
                
            case .vibrato(let item, let offTimeInBeats):
                guard let midiNoteNumber = midiNote(for: item, transposition: transposition) else { continue }
                let noteOnTime = Double(item.position) * sixteenthNoteDurationInBeats
                let noteDuration = offTimeInBeats - noteOnTime

                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: midiNoteNumber, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(track, noteOnTime, &noteMessage)
                }

                let vibratoDurationBeats = noteDuration
                if vibratoDurationBeats > 0.1 {
                    let vibratoRateHz = 5.0
                    let beatsPerSecond = preset.bpm / 60.0
                    let vibratoRateBeats = vibratoRateHz / beatsPerSecond
                    
                    let maxBendSemitones = 0.4
                    let pitchBendRangeSemitones = 2.0
                    let maxPitchBendAmount = (maxBendSemitones / pitchBendRangeSemitones) * 8191.0
                    let totalCycles = vibratoDurationBeats * vibratoRateBeats
                    let totalSteps = Int(totalCycles * 20.0)

                    if totalSteps > 0 {
                        for step in 0...totalSteps {
                            let t_duration = Double(step) / Double(totalSteps)
                            let t_angle = t_duration * totalCycles * 2.0 * .pi
                            let sineValue = sin(t_angle)
                            let pitchBendValue = 8192 + Int(sineValue * maxPitchBendAmount)
                            let bendTime = noteOnTime + t_duration * vibratoDurationBeats
                            
                            var pitchBendMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(pitchBendValue & 0x7F), data2: UInt8((pitchBendValue >> 7) & 0x7F), reserved: 0)
                            MusicTrackNewMIDIChannelEvent(track, bendTime, &pitchBendMessage)
                        }
                    }
                }
                
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(track, offTimeInBeats + 0.01, &pitchBendResetMessage)
                
            case .bend(let fromItem, let toItem, let offTimeInBeats):
                guard let startMidiNote = midiNote(for: fromItem, transposition: transposition) else { continue }
                
                let noteOnTime = Double(fromItem.position) * sixteenthNoteDurationInBeats
                let noteDuration = offTimeInBeats - noteOnTime

                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: startMidiNote, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(track, noteOnTime, &noteMessage)
                }

                let intervalBeats = Double(toItem.position) * sixteenthNoteDurationInBeats - noteOnTime
                if intervalBeats > 0.1 {
                    let quarterIntervalBeats = intervalBeats / 4.0
                    let bendUpStartTimeBeats = noteOnTime + quarterIntervalBeats
                    let bendUpDurationBeats = quarterIntervalBeats
                    let releaseStartTimeBeats = bendUpStartTimeBeats + bendUpDurationBeats
                    let releaseDurationBeats = quarterIntervalBeats

                    let bendAmountSemitones = 2.0
                    let pitchBendRangeSemitones = 2.0
                    let finalPitchBendValue = 8192 + Int(bendAmountSemitones * (8191.0 / pitchBendRangeSemitones))
                    let pitchBendSteps = 10

                    // Bend Up
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTime = bendUpStartTimeBeats + t * bendUpDurationBeats
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        var msg = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(intermediatePitch & 0x7F), data2: UInt8((intermediatePitch >> 7) & 0x7F), reserved: 0)
                        MusicTrackNewMIDIChannelEvent(track, bendTime, &msg)
                    }

                    // Bend Down (Release)
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTime = releaseStartTimeBeats + t * releaseDurationBeats
                        let intermediatePitch = finalPitchBendValue - Int(Double(finalPitchBendValue - 8192) * t)
                        var msg = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(intermediatePitch & 0x7F), data2: UInt8((intermediatePitch >> 7) & 0x7F), reserved: 0)
                        MusicTrackNewMIDIChannelEvent(track, bendTime, &msg)
                    }
                }
                
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(track, offTimeInBeats + 0.01, &pitchBendResetMessage)
            }
        }
        
        return sequence
    }

    private func midiNote(for item: MelodicLyricItem, transposition: Int) -> UInt8? {
        let scaleOffsets: [Int: Int] = [
            1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11 // Major scale intervals
        ]
        guard item.pitch > 0, let scaleOffset = scaleOffsets[item.pitch] else { return nil }
        
        let baseMidiNote = 60 + transposition // C4 + key transposition
        let octaveOffset = item.octave * 12
        return UInt8(baseMidiNote + scaleOffset + octaveOffset)
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
