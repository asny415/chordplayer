import Foundation
import Combine

class SoloPlayer: ObservableObject, Quantizable {
    // Dependencies
    private var midiManager: MidiManager
    var appData: AppData

    // Playback State
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0
    
    private var activeNotes: Set<UInt8> = []
    private var scheduledEventIDs: [UUID] = []
    private var playbackStartDate: Date?
    private var uiTimerCancellable: AnyCancellable?
    private var currentlyPlayingSegmentID: UUID?

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(from: SoloNote, to: SoloNote, offTime: Double)
        case bend(from: SoloNote, to: SoloNote, offTime: Double)
    }
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    var drumPlayer: DrumPlayer

    init(midiManager: MidiManager, appData: AppData, drumPlayer: DrumPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.drumPlayer = drumPlayer
    }

    func play(segment: SoloSegment, quantization: QuantizationMode) {
        if isPlaying && currentlyPlayingSegmentID == segment.id {
            stopPlayback()
            return
        }
        
        stopPlayback()

        let schedulingStartUptimeMs = nextQuantizationTime(for: quantization)
        let delay = (schedulingStartUptimeMs - ProcessInfo.processInfo.systemUptime * 1000.0) / 1000.0

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (delay > 0 ? delay : 0)) { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isPlaying = true
                self.currentlyPlayingSegmentID = segment.id
            }

            let bpm = self.appData.preset?.bpm ?? 120.0
            let beatsToSeconds = 60.0 / bpm
            let playbackStartTimeMs = schedulingStartUptimeMs
            
            let notesSortedByTime = segment.notes.sorted { $0.startTime < $1.startTime }
            let transposition = self.transposition(forKey: self.appData.preset?.key ?? "C")

            var eventIDs: [UUID] = []
            self.activeNotes.removeAll()

            for note in notesSortedByTime {
                guard note.fret >= 0 else { continue }

                let noteDuration = note.duration ?? 1.0
                let noteOnTime = note.startTime
                let noteOffTime = note.startTime + noteDuration

                let midiNoteNumber = self.midiNote(from: note.string, fret: note.fret, transposition: transposition)
                let velocity = UInt8(note.velocity)
                let noteOnTimeMs = playbackStartTimeMs + (noteOnTime * beatsToSeconds * 1000.0)
                let noteOffTimeMs = playbackStartTimeMs + (noteOffTime * beatsToSeconds * 1000.0)

                if noteOffTimeMs > noteOnTimeMs {
                    eventIDs.append(self.midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs))
                    eventIDs.append(self.midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs))
                    self.activeNotes.insert(midiNoteNumber)
                }
            }

            self.scheduledEventIDs = eventIDs

            DispatchQueue.main.async {
                self.playbackStartDate = Date()
                self.uiTimerCancellable = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self = self, let startDate = self.playbackStartDate else { return }
                    let elapsedSeconds = Date().timeIntervalSince(startDate)
                    let beatsPerSecond = (self.appData.preset?.bpm ?? 120.0) / 60.0
                    self.playbackPosition = elapsedSeconds * beatsPerSecond
                    
                    if self.playbackPosition > segment.lengthInBeats {
                        self.stopPlayback()
                    }
                }
            }
        }
    }


    func stopPlayback() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentlyPlayingSegmentID = nil
            self.uiTimerCancellable?.cancel()
            self.playbackStartDate = nil
            self.playbackPosition = 0
        }
        
        midiManager.cancelAllPendingScheduledEvents()
        
        // Send Note Off for all notes that were scheduled to play
        for note in activeNotes {
            midiManager.sendNoteOff(note: note, velocity: 0)
        }
        
        midiManager.sendPitchBend(value: 8192) // Reset pitch bend
        
        activeNotes.removeAll()
        scheduledEventIDs.removeAll()
    }
    
    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        // The notes in SoloSegment are relative to C major scale.
        // We need to transpose them to the preset's key.
        // The transposition should be `keyMap[key] ?? 0`.
        // For example, if the key is "D", the transposition is 2.
        // A C note (fret 1 on string 1) should become a D note.
        // The midi note for C is 60. The midi note for D is 62.
        // So we need to add 2 to the midi note.
        return keyMap[key] ?? 0
    }

    private func midiNote(from string: Int, fret: Int, transposition: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        let baseNote = openStringMIDINotes[string] + UInt8(fret)
        return baseNote + UInt8(transposition)
    }

    
}
