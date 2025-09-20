
import Foundation
import Combine

/// `MelodicLyricPlayer` is responsible for interpreting a `MelodicLyricSegment` and scheduling all the necessary MIDI events to play it back.
/// It handles various playing techniques like slides, bends, and vibrato by generating appropriate MIDI note and pitch bend commands.
/// This class is designed to be a stateless service; it takes a segment and playback parameters, and returns the UUIDs of the scheduled MIDI events.
/// The caller is responsible for managing these event IDs, for instance, to cancel them later.
class MelodicLyricPlayer {
    private var midiManager: MidiManager

    init(midiManager: MidiManager) {
        self.midiManager = midiManager
    }

    /// Schedules the playback of a melodic lyric segment.
    /// - Parameters:
    ///   - segment: The `MelodicLyricSegment` to be played.
    ///   - preset: The `Preset` containing context like BPM and key.
    ///   - channel: The MIDI channel to play the notes on.
    ///   - volume: The playback volume (0.0 to 1.0).
    ///   - startTime: The absolute `TimeInterval` (from `ProcessInfo.processInfo.systemUptime`) when the playback should start.
    /// - Returns: An array of `UUID`s for all the scheduled MIDI events. The caller can use these to cancel the events if needed.
    func schedulePlayback(
        segment: MelodicLyricSegment,
        preset: Preset,
        channel: Int,
        volume: Double,
        startTime: TimeInterval
    ) -> [UUID] {
        
        // Internal enum to represent the musical actions to be performed.
        enum MusicalAction {
            case playNote(item: MelodicLyricItem, offTime: Double)
            case slide(from: MelodicLyricItem, to: MelodicLyricItem, offTime: Double)
            case vibrato(from: MelodicLyricItem, to: MelodicLyricItem, offTime: Double)
            case bend(from: MelodicLyricItem, to: MelodicLyricItem, offTime: Double)
        }

        let beatsToSeconds = 60.0 / preset.bpm
        let transposition = self.transposition(forKey: preset.key)
        let sixteenthNoteDurationInBeats = 0.25
        let segmentDurationInBeats = Double(segment.lengthInBars * preset.timeSignature.beatsPerMeasure)

        let itemsSortedByTime = segment.items.sorted { $0.position < $1.position }
        var consumedItemIDs = Set<UUID>()
        var actions: [MusicalAction] = []

        // 1. Build a list of `MusicalAction`s from the segment items.
        // This pass interprets techniques and groups notes together (e.g., a note and its slide target).
        for i in 0..<itemsSortedByTime.count {
            let currentItem = itemsSortedByTime[i]
            if consumedItemIDs.contains(currentItem.id) || currentItem.pitch == 0 { continue }

            var noteOffPosition = segmentDurationInBeats / sixteenthNoteDurationInBeats
            if let nextItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                noteOffPosition = Double(nextItem.position)
            }
            let noteOffTime = noteOffPosition * sixteenthNoteDurationInBeats

            if currentItem.technique == .slide,
               let targetItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                consumedItemIDs.insert(targetItem.id)
                let offPosition = itemsSortedByTime.firstIndex(of: targetItem).flatMap { itemsSortedByTime.dropFirst($0 + 1).first(where: { $0.pitch > 0 })?.position } ?? Int(segmentDurationInBeats / sixteenthNoteDurationInBeats)
                let offTime = Double(offPosition) * sixteenthNoteDurationInBeats
                actions.append(.slide(from: currentItem, to: targetItem, offTime: offTime))

            } else if currentItem.technique == .vibrato,
                      let targetItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                consumedItemIDs.insert(targetItem.id)
                let offPosition = itemsSortedByTime.firstIndex(of: targetItem).flatMap { itemsSortedByTime.dropFirst($0 + 1).first(where: { $0.pitch > 0 })?.position } ?? Int(segmentDurationInBeats / sixteenthNoteDurationInBeats)
                let offTime = Double(offPosition) * sixteenthNoteDurationInBeats
                actions.append(.vibrato(from: currentItem, to: targetItem, offTime: offTime))

            } else if currentItem.technique == .bend,
                      let targetItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                consumedItemIDs.insert(targetItem.id)
                let offPosition = itemsSortedByTime.firstIndex(of: targetItem).flatMap { itemsSortedByTime.dropFirst($0 + 1).first(where: { $0.pitch > 0 })?.position } ?? Int(segmentDurationInBeats / sixteenthNoteDurationInBeats)
                let offTime = Double(offPosition) * sixteenthNoteDurationInBeats
                actions.append(.bend(from: currentItem, to: targetItem, offTime: offTime))
            
            } else {
                actions.append(.playNote(item: currentItem, offTime: noteOffTime))
            }
        }
        
        var allEventIDs: [UUID] = []

        // 2. Process the actions and schedule the corresponding MIDI events.
        for action in actions {
            var eventIDs: [UUID] = []
            let midiChannel = UInt8(channel - 1)
            let velocity = UInt8(min(127, max(1, Int(100 * volume))))

            switch action {
            case .playNote(let item, let offTime):
                guard let midiNote = midiNote(for: item, transposition: transposition) else { continue }
                let noteOnTimeMs = (startTime + Double(item.position) * sixteenthNoteDurationInBeats * beatsToSeconds) * 1000
                let noteOffTimeMs = (startTime + offTime * beatsToSeconds) * 1000

                if noteOffTimeMs > noteOnTimeMs {
                    eventIDs.append(midiManager.scheduleNoteOn(note: midiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTimeMs))
                    eventIDs.append(midiManager.scheduleNoteOff(note: midiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeMs))
                }

            case .slide(let fromItem, let toItem, let offTime):
                guard let startMidiNote = midiNote(for: fromItem, transposition: transposition),
                      let endMidiNote = midiNote(for: toItem, transposition: transposition) else { continue }
                
                let noteOnTime = startTime + Double(fromItem.position) * sixteenthNoteDurationInBeats * beatsToSeconds
                let noteOffTimeAbsolute = startTime + offTime * beatsToSeconds

                eventIDs.append(midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))

                let slideDurationBeats = Double(toItem.position - fromItem.position) * sixteenthNoteDurationInBeats
                if slideDurationBeats > 0 {
                    let slideDurationSeconds = slideDurationBeats * beatsToSeconds
                    let pitchBendSteps = max(2, Int(slideDurationSeconds * 50))
                    let semitoneDifference = Int(endMidiNote) - Int(startMidiNote)
                    let pitchBendRangeSemitones = 2.0 // Standard pitch bend range
                    let finalPitchBendValue = 8192 + Int(Double(semitoneDifference) * (8191.0 / pitchBendRangeSemitones))

                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTimeMs = (noteOnTime + t * slideDurationSeconds) * 1000
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        eventIDs.append(midiManager.schedulePitchBend(value: UInt16(intermediatePitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                    }
                }
                
                eventIDs.append(midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeAbsolute * 1000))
                eventIDs.append(midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (noteOffTimeAbsolute + 0.01) * 1000))


            case .vibrato(let fromItem, _, let offTime):
                guard let midiNote = midiNote(for: fromItem, transposition: transposition) else { continue }
                let noteOnTime = startTime + Double(fromItem.position) * sixteenthNoteDurationInBeats * beatsToSeconds
                let noteOffTimeAbsolute = startTime + offTime * beatsToSeconds

                eventIDs.append(midiManager.scheduleNoteOn(note: midiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))

                let vibratoDurationSeconds = noteOffTimeAbsolute - noteOnTime
                if vibratoDurationSeconds > 0.1 {
                    let vibratoRateHz = 5.0
                    let maxBendSemitones = 0.4
                    let pitchBendRangeSemitones = 2.0
                    let maxPitchBendAmount = (maxBendSemitones / pitchBendRangeSemitones) * 8191.0
                    let totalCycles = vibratoDurationSeconds * vibratoRateHz
                    let totalSteps = Int(totalCycles * 20.0) // 20 steps per cycle for smoothness

                    if totalSteps > 0 {
                        for step in 0...totalSteps {
                            let t_duration = Double(step) / Double(totalSteps)
                            let t_angle = t_duration * totalCycles * 2.0 * .pi
                            let sineValue = sin(t_angle)
                            let pitchBendValue = 8192 + Int(sineValue * maxPitchBendAmount)
                            let bendTimeMs = (noteOnTime + t_duration * vibratoDurationSeconds) * 1000
                            eventIDs.append(midiManager.schedulePitchBend(value: UInt16(pitchBendValue), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                        }
                    }
                }

                eventIDs.append(midiManager.scheduleNoteOff(note: midiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeAbsolute * 1000))
                eventIDs.append(midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (noteOffTimeAbsolute + 0.01) * 1000))

            case .bend(let fromItem, let toItem, let offTime):
                guard let startMidiNote = midiNote(for: fromItem, transposition: transposition) else { continue }
                let noteOnTime = startTime + Double(fromItem.position) * sixteenthNoteDurationInBeats * beatsToSeconds
                let noteOffTimeAbsolute = startTime + offTime * beatsToSeconds

                eventIDs.append(midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, channel: midiChannel, scheduledUptimeMs: noteOnTime * 1000))

                let intervalBeats = Double(toItem.position - fromItem.position) * sixteenthNoteDurationInBeats
                if intervalBeats > 0.1 {
                    // Perform a classic "bend and release" within the note's duration
                    let quarterIntervalBeats = intervalBeats / 4.0
                    
                    let bendUpStartTimeBeats = Double(fromItem.position) * sixteenthNoteDurationInBeats + quarterIntervalBeats
                    let bendUpDurationBeats = quarterIntervalBeats
                    
                    let releaseStartTimeBeats = bendUpStartTimeBeats + bendUpDurationBeats
                    let releaseDurationBeats = quarterIntervalBeats

                    let bendAmountSemitones = 1.0 // Bend up by a whole step
                    let pitchBendRangeSemitones = 2.0
                    let finalPitchBendValue = 8192 + Int(bendAmountSemitones * (8191.0 / pitchBendRangeSemitones))
                    
                    let pitchBendSteps = 10

                    // Bend Up
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTimeMs = (startTime + (bendUpStartTimeBeats + t * bendUpDurationBeats) * beatsToSeconds) * 1000
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        eventIDs.append(midiManager.schedulePitchBend(value: UInt16(intermediatePitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                    }

                    // Bend Down (Release)
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTimeMs = (startTime + (releaseStartTimeBeats + t * releaseDurationBeats) * beatsToSeconds) * 1000
                        let intermediatePitch = finalPitchBendValue - Int(Double(finalPitchBendValue - 8192) * t)
                        eventIDs.append(midiManager.schedulePitchBend(value: UInt16(intermediatePitch), channel: midiChannel, scheduledUptimeMs: bendTimeMs))
                    }
                }

                eventIDs.append(midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, channel: midiChannel, scheduledUptimeMs: noteOffTimeAbsolute * 1000))
                eventIDs.append(midiManager.schedulePitchBend(value: 8192, channel: midiChannel, scheduledUptimeMs: (noteOffTimeAbsolute + 0.01) * 1000))
            }
            allEventIDs.append(contentsOf: eventIDs)
        }
        
        return allEventIDs
    }
    
    // MARK: - Private Helper Methods

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
