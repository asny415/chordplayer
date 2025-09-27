import Foundation
import Combine
import AudioToolbox

class SoloPlayer: ObservableObject {
    // MARK: - Dependencies
    private var midiSequencer: MIDISequencer
    private var midiManager: MidiManager
    var appData: AppData

    // MARK: - Playback State
    @Published var isPlaying: Bool = false
    private var currentlyPlayingSegmentID: UUID?
    private var cancellables = Set<AnyCancellable>()

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(note: SoloNote, offTime: Double)
        case bend(from: SoloNote, to: SoloNote, offTime: Double)
    }
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    init(midiSequencer: MIDISequencer, midiManager: MidiManager, appData: AppData) {
        self.midiSequencer = midiSequencer
        self.midiManager = midiManager
        self.appData = appData
        print("[SoloPlayer] Initialized.")
        
        // Subscribe to sequencer's isPlaying state
        self.midiSequencer.$isPlaying.sink { [weak self] sequencerIsPlaying in
            print("[SoloPlayer] Sink received: midiSequencer.isPlaying is now \(sequencerIsPlaying)")
            if !sequencerIsPlaying {
                self?.isPlaying = false
                self?.currentlyPlayingSegmentID = nil
                print("[SoloPlayer] Sink updated self.isPlaying to false.")
            }
        }.store(in: &cancellables)
    }

    func play(segment: SoloSegment, channel: UInt8 = 0) {
        print("[SoloPlayer] play() called.")
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            print("[SoloPlayer] play() -> stopping existing playback.")
            stop()
            return
        }
        
        print("[SoloPlayer] play() -> stopping any previous playback.")
        stop() // Stop any previous playback

        // Set the pitch bend range for the channel before playing
        midiManager.setPitchBendRange(channel: channel, rangeInSemitones: 2)

        guard let sequence = createSequence(from: segment, onChannel: channel),
              let endpoint = midiManager.selectedOutput else {
            print("Failed to create sequence or get MIDI endpoint.")
            return
        }
        
        midiSequencer.play(sequence: sequence, on: endpoint)
        
        // Update local state
        print("[SoloPlayer] play() -> setting self.isPlaying = true")
        self.isPlaying = true
        self.currentlyPlayingSegmentID = segment.id
    }

    func stop() {
        print("[SoloPlayer] stop() called.")
        midiSequencer.stop()
        // Directly update state here to be more robust, not just relying on the sink.
        if isPlaying {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
            print("[SoloPlayer] stop() updated self.isPlaying to false.")
        }
    }
    
    private func createSequence(from segment: SoloSegment, onChannel midiChannel: UInt8) -> MusicSequence? {
        var musicSequence: MusicSequence?
        var status = NewMusicSequence(&musicSequence)
        guard status == noErr, let sequence = musicSequence else { return nil }

        let bpm = appData.preset?.bpm ?? 120.0

        // Get the tempo track and set the BPM.
        var tempoTrack: MusicTrack?
        if MusicSequenceGetTempoTrack(sequence, &tempoTrack) == noErr, let tempoTrack = tempoTrack {
            status = MusicTrackNewExtendedTempoEvent(tempoTrack, 0.0, bpm)
            if status != noErr {
                print("Failed to set tempo. Status: \(status)")
                // Not returning nil here, as we can proceed without the tempo event if needed.
            }
        } else {
            print("Failed to get tempo track.")
        }

        var musicTrack: MusicTrack?
        status = MusicSequenceNewTrack(sequence, &musicTrack)
        guard status == noErr, let musicTrack = musicTrack else { return nil }

        let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
        let transposition = self.transposition(forKey: appData.preset?.key ?? "C")

        var consumedNoteIDs = Set<UUID>()
        var actions: [MusicalAction] = []

        // 1. Build a list of `MusicalAction`s (reusing existing logic)
        for i in 0..<notesSortedByTime.count {
            let currentNote = notesSortedByTime[i]
            if consumedNoteIDs.contains(currentNote.id) || currentNote.fret < 0 { continue }

            let noteOffTime: Double
            if let nextNoteOnSameString = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                noteOffTime = nextNoteOnSameString.startTime
            } else {
                noteOffTime = currentNote.startTime + (currentNote.duration ?? 1.0)
            }

            switch currentNote.technique {
            case .slide:
                if let targetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                    consumedNoteIDs.insert(targetNote.id)
                    let slideOffTime = targetNote.startTime + (targetNote.duration ?? 1.0)
                    actions.append(.slide(from: currentNote, to: targetNote, offTime: slideOffTime))
                } else {
                    actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                }
            case .bend:
                 if let targetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                    consumedNoteIDs.insert(targetNote.id)
                    let bendOffTime = targetNote.startTime + (targetNote.duration ?? 1.0)
                    actions.append(.bend(from: currentNote, to: targetNote, offTime: bendOffTime))
                } else {
                    actions.append(.playNote(note: currentNote, offTime: noteOffTime))
                }
            case .vibrato:
                actions.append(.vibrato(note: currentNote, offTime: noteOffTime))
            case .normal:
                actions.append(.playNote(note: currentNote, offTime: noteOffTime))
            }
        }

        // 2. Process actions and add events to the MusicTrack
        for action in actions {
            let velocity = UInt8(100)

            switch action {
            case .playNote(let note, let offTime):
                let midiNoteNumber = midiNote(from: note.string, fret: note.fret, transposition: transposition)
                let duration = offTime - note.startTime
                if duration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: midiNoteNumber, velocity: velocity, releaseVelocity: 0, duration: Float(duration))
                    MusicTrackNewMIDINoteEvent(musicTrack, note.startTime, &noteMessage)
                }

            case .slide(let fromNote, let toNote, let offTime):
                let startMidiNote = midiNote(from: fromNote.string, fret: fromNote.fret, transposition: transposition)
                let endMidiNote = midiNote(from: toNote.string, fret: toNote.fret, transposition: transposition)
                let semitoneDifference = Int(endMidiNote) - Int(startMidiNote)
                let pitchBendRangeSemitones = 2.0

                let noteOnTime = fromNote.startTime
                let slideTargetTime = toNote.startTime
                let finalNoteOffTime = offTime
                let noteDuration = finalNoteOffTime - noteOnTime

                // Pluck the first note
                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: startMidiNote, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(musicTrack, noteOnTime, &noteMessage)
                }

                // Add pitch bend events
                let slideDurationBeats = slideTargetTime - noteOnTime
                if slideDurationBeats > 0.01 && abs(semitoneDifference) > 0 {
                    let finalPitchBendValue = 8192 + Int(Double(semitoneDifference) * (8191.0 / pitchBendRangeSemitones))
                    let pitchBendSteps = max(2, Int(slideDurationBeats * 50)) // 50 steps per beat
                    
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTime = noteOnTime + t * slideDurationBeats
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        let clampedPitch = max(0, min(16383, intermediatePitch))
                        
                        var pitchBendMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(clampedPitch & 0x7F), data2: UInt8((clampedPitch >> 7) & 0x7F), reserved: 0)
                        MusicTrackNewMIDIChannelEvent(musicTrack, bendTime, &pitchBendMessage)
                    }
                }
                
                // Reset bend after the note is off
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(musicTrack, finalNoteOffTime + 0.01, &pitchBendResetMessage)

            case .vibrato(let note, let offTime):
                let midiNoteNumber = midiNote(from: note.string, fret: note.fret, transposition: transposition)
                let noteOnTime = note.startTime
                let noteDuration = offTime - noteOnTime

                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: midiNoteNumber, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(musicTrack, noteOnTime, &noteMessage)
                }

                let vibratoDurationBeats = noteDuration
                if vibratoDurationBeats > 0.1 {
                    let vibratoRateHz = 5.0
                    let beatsPerSecond = bpm / 60.0
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
                            MusicTrackNewMIDIChannelEvent(musicTrack, bendTime, &pitchBendMessage)
                        }
                    }
                }
                
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(musicTrack, offTime + 0.01, &pitchBendResetMessage)

            case .bend(let fromNote, let toNote, let offTime):
                let startMidiNote = midiNote(from: fromNote.string, fret: fromNote.fret, transposition: transposition)
                let noteOnTime = fromNote.startTime
                let noteDuration = offTime - noteOnTime

                if noteDuration > 0 {
                    var noteMessage = MIDINoteMessage(channel: midiChannel, note: startMidiNote, velocity: velocity, releaseVelocity: 0, duration: Float(noteDuration))
                    MusicTrackNewMIDINoteEvent(musicTrack, noteOnTime, &noteMessage)
                }

                let intervalBeats = toNote.startTime - fromNote.startTime
                if intervalBeats > 0.1 {
                    let quarterIntervalBeats = intervalBeats / 4.0
                    let bendUpStartTimeBeats = fromNote.startTime + quarterIntervalBeats
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
                        MusicTrackNewMIDIChannelEvent(musicTrack, bendTime, &msg)
                    }

                    // Bend Down (Release)
                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let bendTime = releaseStartTimeBeats + t * releaseDurationBeats
                        let intermediatePitch = finalPitchBendValue - Int(Double(finalPitchBendValue - 8192) * t)
                        var msg = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: UInt8(intermediatePitch & 0x7F), data2: UInt8((intermediatePitch >> 7) & 0x7F), reserved: 0)
                        MusicTrackNewMIDIChannelEvent(musicTrack, bendTime, &msg)
                    }
                }
                
                var pitchBendResetMessage = MIDIChannelMessage(status: 0xE0 | midiChannel, data1: 0, data2: 64, reserved: 0) // 8192
                MusicTrackNewMIDIChannelEvent(musicTrack, offTime + 0.01, &pitchBendResetMessage)
            }
        }
        
        return sequence
    }

    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        return keyMap[key] ?? 0
    }

    private func midiNote(from string: Int, fret: Int, transposition: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        let baseNote = openStringMIDINotes[string] + UInt8(fret)
        return baseNote + UInt8(transposition)
    }
}