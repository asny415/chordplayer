import Foundation
import Combine

class ChordPlayer: ObservableObject {
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    private var appData: AppData

    private var playingNotes: [UInt8: UUID] = [:] // Maps MIDI Note -> Scheduled Note-Off Task ID
    private var stringNotes: [Int: UInt8] = [:] // Maps String Index (0-5) -> MIDI Note
    private var scheduledUIUpdateWorkItem: DispatchWorkItem?

    init(midiManager: MidiManager, appData: AppData) {
        self.midiManager = midiManager
        self.appData = appData
    }

    func playChord(chordName: String, pattern: GuitarPattern, tempo: Double = 120.0, key: String = "C", capo: Int = 0, velocity: UInt8 = 100, duration: TimeInterval = 0.5, quantizationMode: QuantizationMode = .none, drumClockInfo: (isPlaying: Bool, startTime: Double, loopDuration: Double)? = nil) {
        print("[ChordPlayer] playChord called for chord: \(chordName), pattern: \(pattern.name)")
        guard let chordDefinition = appData.chordLibrary?[chordName] else {
            print("[ChordPlayer] Chord definition for \(chordName) not found.")
            return
        }

        var transposeOffset = 0
        if let idx = appData.KEY_CYCLE.firstIndex(of: key) {
            transposeOffset = idx
        }

        var midiNotes: [Int] = Array(repeating: -1, count: 6)
        for (i, fretVal) in chordDefinition.enumerated() {
            switch fretVal {
            case .int(let fretInt):
                if fretInt >= 0 { // Consider 'x' or negative as muted
                    midiNotes[i] = MusicTheory.standardGuitarTuning[i] + fretInt + transposeOffset + capo
                }
            case .string:
                midiNotes[i] = -1
            }
        }
        print("[ChordPlayer] Resolved MIDI notes for chord \(chordName): \(midiNotes)")

        let wholeNoteSeconds = (60.0 / tempo) * 4.0
        var schedulingStartUptimeMs: Double
        let currentUptime = ProcessInfo.processInfo.systemUptime * 1000.0

        if quantizationMode != .none, let clock = drumClockInfo, clock.isPlaying, clock.loopDuration > 0 {
            let elapsedTime = currentUptime - clock.startTime
            var quantizationUnitDuration: Double
            var nextQuantizationTime: Double

            switch quantizationMode {
            case .measure:
                quantizationUnitDuration = clock.loopDuration
            case .halfMeasure:
                quantizationUnitDuration = clock.loopDuration / 2.0
            case .none:
                schedulingStartUptimeMs = currentUptime
                return // Should not happen
            }

            let numUnitsCompleted = floor(elapsedTime / quantizationUnitDuration)
            nextQuantizationTime = clock.startTime + (numUnitsCompleted + 1) * quantizationUnitDuration

            if nextQuantizationTime < currentUptime {
                nextQuantizationTime += quantizationUnitDuration
            }

            let timeToNextQuantization = nextQuantizationTime - currentUptime
            let quantizationWindow = quantizationUnitDuration / 2.0

            if timeToNextQuantization > quantizationWindow {
                print("[ChordPlayer] Discarding chord playback: outside quantization window. Time to next: \(timeToNextQuantization)ms, window: \(quantizationWindow)ms")
                return
            }
            
            schedulingStartUptimeMs = nextQuantizationTime
            print("[ChordPlayer] Quantized scheduling start uptime: \(schedulingStartUptimeMs)ms")

        } else {
            schedulingStartUptimeMs = currentUptime
            print("[ChordPlayer] Non-quantized scheduling start uptime: \(schedulingStartUptimeMs)ms")
        }

        // Schedule the UI update to be perfectly in sync with the audio
        scheduledUIUpdateWorkItem?.cancel()
        let delayMs = max(0, schedulingStartUptimeMs - currentUptime)
        let workItem = DispatchWorkItem { [weak self] in
            self?.appData.currentlyPlayingChordName = chordName
            self?.appData.currentlyPlayingPatternName = pattern.name
            print("[ChordPlayer] UI updated for chord: \(chordName)")
        }
        scheduledUIUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(round(delayMs))), execute: workItem)

        // Stop notes on strings that will be silent in the new chord.
        for (stringIndex, note) in stringNotes {
            if midiNotes[stringIndex] == -1 { // If the string is muted in the new chord
                print("[ChordPlayer] String \(stringIndex) is muted. Stopping previous note \(note).")
                if let scheduledOffId = playingNotes[note] {
                    midiManager.cancelScheduledEvent(id: scheduledOffId)
                    playingNotes.removeValue(forKey: note)
                    print("[ChordPlayer] Cancelled scheduled note-off for \(note).")
                }
                midiManager.sendNoteOff(note: note, velocity: 0, channel: 0)
                stringNotes.removeValue(forKey: stringIndex)
            }
        }

        for event in pattern.pattern {
            guard let delayFraction = MusicTheory.parseDelay(delayString: event.delay) else {
                print("[ChordPlayer] Could not parse delay string: \(event.delay)")
                continue
            }
            let eventBaseTimeMs = schedulingStartUptimeMs + (delayFraction * wholeNoteSeconds * 1000.0)
            print("[ChordPlayer] Pattern event delay: \(event.delay), base time: \(eventBaseTimeMs)ms")

            var notesToSchedule: [(note: UInt8, stringIndex: Int)] = []

            // Find root note info for resolving .chordRoot notes
            var rootInfo: (stringIndex: Int, midiNote: Int)?
            for (index, note) in midiNotes.enumerated() {
                if note != -1 {
                    rootInfo = (stringIndex: index, midiNote: note)
                    break
                }
            }

            for noteValue in event.notes {
                var resolvedNote: (note: Int, stringIndex: Int)?

                switch noteValue {
                case .chordString(let stringNumber):
                    // stringNumber is 1-6, convert to index 0-5
                    let stringIndex = 6 - stringNumber
                    if stringIndex >= 0 && stringIndex < midiNotes.count && midiNotes[stringIndex] != -1 {
                        resolvedNote = (note: midiNotes[stringIndex], stringIndex: stringIndex)
                        print("[ChordPlayer] Resolved .chordString \(stringNumber) to MIDI note \(midiNotes[stringIndex]) on string \(stringIndex)")
                    }

                case .chordRoot(let symbol):
                    guard let unwrappedRootInfo = rootInfo else { continue }
                    if symbol.starts(with: "ROOT") {
                        let numPart = symbol.replacingOccurrences(of: "ROOT", with: "").replacingOccurrences(of: "-", with: "")
                        var offset = 0
                        if !numPart.isEmpty, let num = Int(numPart) {
                            offset = num
                        }
                        let targetStringIndex = unwrappedRootInfo.stringIndex + offset
                        if targetStringIndex >= 0 && targetStringIndex < midiNotes.count, midiNotes[targetStringIndex] != -1 {
                            resolvedNote = (note: midiNotes[targetStringIndex], stringIndex: targetStringIndex)
                            print("[ChordPlayer] Resolved .chordRoot \(symbol) to MIDI note \(midiNotes[targetStringIndex]) on string \(targetStringIndex)")
                        }
                    }
                
                case .specificFret(let string, let fret):
                    // string is 1-6, convert to index 0-5
                    let stringIndex = 6 - string
                    if stringIndex >= 0 && stringIndex < MusicTheory.standardGuitarTuning.count {
                        let baseNote = MusicTheory.standardGuitarTuning[stringIndex]
                        // Apply same transpose and capo as the rest of the chord for consistency
                        let finalNote = baseNote + fret + transposeOffset + capo
                        resolvedNote = (note: finalNote, stringIndex: stringIndex)
                        print("[ChordPlayer] Resolved .specificFret string \(string), fret \(fret) to MIDI note \(finalNote) on string \(stringIndex)")
                    }
                }
                
                if let note = resolvedNote {
                    notesToSchedule.append((note: UInt8(note.note), stringIndex: note.stringIndex))
                }
            }
            print("[ChordPlayer] Notes to schedule for this event: \(notesToSchedule.map { "\($0.note) (string \($0.stringIndex))" }.joined(separator: ", "))")

            // Calculate adaptive velocity based on the number of notes being played simultaneously
            let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocity, noteCount: notesToSchedule.count)
            
            for (i, item) in notesToSchedule.enumerated() {
                var strumOffsetMs: Double = 0
                if let delta = event.delta {
                    strumOffsetMs = delta * Double(i)
                }

                let scheduledNoteOnUptimeMs = eventBaseTimeMs + strumOffsetMs
                
                // If a note is already playing on this string, cancel its scheduled note-off and send an immediate NoteOff.
                if let previousNote = self.stringNotes[item.stringIndex] {
                    print("[ChordPlayer] String \(item.stringIndex) already playing note \(previousNote).")
                    if let scheduledOffId = self.playingNotes[previousNote] {
                        self.midiManager.cancelScheduledEvent(id: scheduledOffId)
                        self.playingNotes.removeValue(forKey: previousNote)
                        print("[ChordPlayer] Cancelled scheduled note-off for previous note \(previousNote).")
                    }
                    // Send an immediate NoteOff for the previous note to ensure re-triggering.
                    self.midiManager.sendNoteOff(note: previousNote, velocity: 0, channel: 0)
                    print("[ChordPlayer] Sent immediate NoteOff for previous note \(previousNote) on string \(item.stringIndex).")
                }

                self.midiManager.scheduleNoteOn(note: item.note, velocity: adaptiveVelocity, channel: 0, scheduledUptimeMs: scheduledNoteOnUptimeMs)
                self.stringNotes[item.stringIndex] = item.note
                print("[ChordPlayer] Scheduled NoteOn for MIDI note \(item.note) on string \(item.stringIndex) at \(scheduledNoteOnUptimeMs)ms.")

                let scheduledNoteOffUptimeMs = scheduledNoteOnUptimeMs + (duration * 1000.0)
                let offId = self.midiManager.scheduleNoteOff(note: item.note, velocity: 0, channel: 0, scheduledUptimeMs: scheduledNoteOffUptimeMs)
                
                self.playingNotes[item.note] = offId
                print("[ChordPlayer] Scheduled NoteOff for MIDI note \(item.note) at \(scheduledNoteOffUptimeMs)ms (ID: \(offId)).")
            }
        }
    }

    func panic() {
        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
        playingNotes.removeAll()
        stringNotes.removeAll()
    }
    
    /// Calculates adaptive velocity based on the number of notes being played simultaneously
    /// to prevent volume buildup when multiple notes are played together
    private func calculateAdaptiveVelocity(baseVelocity: UInt8, noteCount: Int) -> UInt8 {
        guard noteCount > 1 else {
            // Single note: use full velocity
            return baseVelocity
        }
        
        // Apply velocity reduction based on note count to prevent volume buildup
        // Formula: adaptiveVelocity = baseVelocity * (1.0 / sqrt(noteCount)) * scalingFactor
        let scalingFactor: Double = 1.2 // Slight boost to maintain presence
        let reductionFactor = 1.0 / sqrt(Double(noteCount))
        let adaptiveVelocity = Double(baseVelocity) * reductionFactor * scalingFactor
        
        // Ensure velocity stays within valid MIDI range (1-127)
        let clampedVelocity = max(1, min(127, Int(round(adaptiveVelocity))))
        
        return UInt8(clampedVelocity)
    }
    
    func playChordDirectly(chordDefinition: [StringOrInt], key: String = "C", capo: Int = 0, velocity: UInt8 = 100, duration: TimeInterval = 2.0) {
        print("[ChordPlayer] playChordDirectly called.")
        let currentUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        var transposeOffset = 0
        if let idx = appData.KEY_CYCLE.firstIndex(of: key) {
            transposeOffset = idx
        }

        var midiNotes: [Int] = Array(repeating: -1, count: 6)
        for (i, fretVal) in chordDefinition.enumerated() {
            switch fretVal {
            case .int(let fretInt):
                if fretInt >= 0 {
                    midiNotes[i] = MusicTheory.standardGuitarTuning[i] + fretInt + transposeOffset + capo
                }
            case .string:
                midiNotes[i] = -1
            }
        }
        print("[ChordPlayer] Resolved MIDI notes for direct play: \(midiNotes)")

        // Count active notes to calculate adaptive velocity
        let activeNotes = midiNotes.filter { $0 != -1 }
        let adaptiveVelocity = calculateAdaptiveVelocity(baseVelocity: velocity, noteCount: activeNotes.count)
        print("[ChordPlayer] Adaptive velocity: \(adaptiveVelocity)")
        
        // Iterate through all 6 strings
        for stringIndex in 0..<6 {
            let newNote = midiNotes[stringIndex]

            // If a note is already playing on this string, cancel its scheduled note-off.
            if let previousNote = self.stringNotes[stringIndex] {
                print("[ChordPlayer] String \(stringIndex) already playing note \(previousNote).")
                if let scheduledOffId = self.playingNotes[previousNote] {
                    self.midiManager.cancelScheduledEvent(id: scheduledOffId)
                    self.playingNotes.removeValue(forKey: previousNote)
                    print("[ChordPlayer] Cancelled scheduled note-off for previous note \(previousNote).")
                }
                // We send an immediate note-off for the previous note to ensure it stops now,
                // as the new chord might not play on this string.
                if newNote == -1 {
                    self.midiManager.sendNoteOff(note: previousNote, velocity: 0, channel: 0)
                    self.stringNotes.removeValue(forKey: stringIndex)
                    print("[ChordPlayer] Sent immediate NoteOff for previous note \(previousNote) on string \(stringIndex).")
                }
            }

            // If there's a new note to play on this string
            if newNote != -1 {
                let noteToPlay = UInt8(newNote)
                
                // Schedule the new note with adaptive velocity
                self.midiManager.scheduleNoteOn(note: noteToPlay, velocity: adaptiveVelocity, channel: 0, scheduledUptimeMs: currentUptimeMs)
                self.stringNotes[stringIndex] = noteToPlay
                print("[ChordPlayer] Scheduled NoteOn for MIDI note \(noteToPlay) on string \(stringIndex) at \(currentUptimeMs)ms.")

                // Schedule the corresponding note-off
                let scheduledNoteOffUptimeMs = currentUptimeMs + (duration * 1000.0)
                let offId = self.midiManager.scheduleNoteOff(note: noteToPlay, velocity: 0, channel: 0, scheduledUptimeMs: scheduledNoteOffUptimeMs)
                
                self.playingNotes[noteToPlay] = offId
                print("[ChordPlayer] Scheduled NoteOff for MIDI note \(noteToPlay) at \(scheduledNoteOffUptimeMs)ms (ID: \(offId)).")
            }
        }
    }
}
