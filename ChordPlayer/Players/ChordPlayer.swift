import Foundation
import Combine

class ChordPlayer: ObservableObject {
    private let schedulingQueue = DispatchQueue(label: "com.guitastudio.guitarScheduler", qos: .userInitiated)
    private var midiManager: MidiManager
    var appData: AppData
    var drumPlayer: DrumPlayer

    private let notesLock = NSRecursiveLock()
    private var scheduledWorkItems: [UUID: DispatchWorkItem] = [:]
    private let workItemsLock = NSRecursiveLock()

    private var playingNotes: [UInt8: UUID] = [:] // Maps MIDI Note -> Scheduled Note-Off Task ID
    private var stringNotes: [Int: UInt8] = [:] // Maps String Index (0-5) -> MIDI Note
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager, appData: AppData, drumPlayer: DrumPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.drumPlayer = drumPlayer
    }

    // MARK: - Public Playback Methods

    func play(segment: AccompanimentSegment) {
        guard let preset = appData.preset else { return }
        panic() // Stop any previous playback

        let secondsPerBeat = 60.0 / preset.bpm
        let playbackStartTime = ProcessInfo.processInfo.systemUptime

        // Create a flat, time-sorted list of all chord events with their absolute start times.
        let absoluteChordEvents = segment.measures.enumerated().flatMap { (measureIndex, measure) -> [TimelineEvent] in
            measure.chordEvents.map { event in
                var absoluteEvent = event
                absoluteEvent.startBeat += measureIndex * preset.timeSignature.beatsPerMeasure
                return absoluteEvent
            }
        }.sorted { $0.startBeat < $1.startBeat }

        // Iterate through each measure and its pattern events.
        for (measureIndex, measure) in segment.measures.enumerated() {
            for patternEvent in measure.patternEvents {
                let absolutePatternStartBeat = measureIndex * preset.timeSignature.beatsPerMeasure + patternEvent.startBeat

                // Find the chord that should be active for this pattern event.
                // It's the last chord event that starts at or before the pattern event.
                let activeChordEvent = absoluteChordEvents.last { $0.startBeat <= absolutePatternStartBeat }

                guard let chordEvent = activeChordEvent else { continue }
                
                // Find the actual Chord and GuitarPattern objects from the preset library.
                guard let chordToPlay = preset.chords.first(where: { $0.id == chordEvent.resourceId }),
                      let patternToPlay = preset.playingPatterns.first(where: { $0.id == patternEvent.resourceId }) else {
                    continue
                }

                let scheduledUptime = playbackStartTime + (Double(absolutePatternStartBeat) * secondsPerBeat)
                let totalDuration = Double(patternEvent.durationInBeats) * secondsPerBeat

                schedulePattern(
                    chord: chordToPlay,
                    pattern: patternToPlay,
                    preset: preset,
                    scheduledUptime: scheduledUptime,
                    totalDuration: totalDuration,
                    dynamics: measure.dynamics,
                    completion: { _ in }
                )
            }
        }
    }

    func previewPattern(_ pattern: GuitarPattern) {
        guard let preset = appData.preset else { return }
        panic()
        let previewChord = Chord(name: "C", frets: [-1, 3, 2, 0, 1, 0], fingers: [])
        
        // Calculate a sensible preview duration based on pattern properties
        let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
        let stepsPerWholeNote = pattern.resolution == .sixteenth ? 16.0 : 8.0
        let singleStepDuration = wholeNoteSeconds / stepsPerWholeNote
        let previewDuration = singleStepDuration * Double(pattern.length)

        schedulePattern(
            chord: previewChord, 
            pattern: pattern, 
            preset: preset, 
            scheduledUptime: ProcessInfo.processInfo.systemUptime,
            totalDuration: previewDuration, 
            dynamics: .medium,
            completion: { _ in }
        )
    }

    func panic() {
        print("[ChordPlayer] PANIC! Cancelling all scheduled events.")
        workItemsLock.lock()
        for item in scheduledWorkItems.values {
            item.cancel()
        }
        scheduledWorkItems.removeAll()
        workItemsLock.unlock()

        notesLock.lock()
        defer { notesLock.unlock() }

        midiManager.sendPanic()
        midiManager.cancelAllPendingScheduledEvents()
        playingNotes.removeAll()
        stringNotes.removeAll()
    }

    // MARK: - Scheduling Logic

    func schedulePattern(chord: Chord, pattern: GuitarPattern, preset: Preset, scheduledUptime: TimeInterval, totalDuration: TimeInterval, dynamics: MeasureDynamics, baseVelocity: UInt8 = 100, midiChannel: Int? = nil, completion: @escaping ([UUID]) -> Void) {
        let delay = scheduledUptime - ProcessInfo.processInfo.systemUptime
        let workItemID = UUID()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return completion([]) }

            var eventIDs: [UUID] = []
            let channel = UInt8((midiChannel ?? self.appData.chordMidiChannel) - 1)
            let transpositionOffset = MusicTheory.KEY_CYCLE.firstIndex(of: preset.key) ?? 0

            var midiNotesForChord: [Int] = Array(repeating: -1, count: 6)
            let fretsForPlayback = Array(chord.frets.reversed())
            for (stringIndex, fret) in fretsForPlayback.enumerated() {
                if fret >= 0 {
                    midiNotesForChord[stringIndex] = MusicTheory.standardGuitarTuning[stringIndex] + fret + transpositionOffset
                }
            }

            // If the pattern is empty, don't try to divide by zero
            let singleStepDurationSeconds = pattern.steps.isEmpty ? totalDuration : (totalDuration / Double(pattern.steps.count))

            DispatchQueue.main.async {
                self.updateCurrentlyPlayingUI(chordName: chord.name)
                self.stopSilentStrings(newChordMidiNotes: midiNotesForChord, channel: channel)
            }

            for (stepIndex, step) in pattern.steps.enumerated() {
                guard !step.activeNotes.isEmpty else { continue }

                let stepStartTimeOffset = Double(stepIndex) * singleStepDurationSeconds

                let activeNotesInStep = step.activeNotes.compactMap { stringIndex -> (note: UInt8, stringIndex: Int)? in
                    var finalFret: Int
                    if let overrideFret = step.fretOverrides[stringIndex] {
                        finalFret = overrideFret
                    } else {
                        guard stringIndex < fretsForPlayback.count else { return nil }
                        finalFret = fretsForPlayback[stringIndex]
                    }

                    guard finalFret >= 0 else { return nil }
                    let noteValue = MusicTheory.standardGuitarTuning[stringIndex] + finalFret + transpositionOffset
                    return (note: UInt8(noteValue), stringIndex: stringIndex)
                }

                guard !activeNotesInStep.isEmpty else { continue }

                let velocityWithDynamics = UInt8(max(1, min(127, Double(baseVelocity) * dynamics.velocityMultiplier)))
                let adaptiveVelocity = self.calculateAdaptiveVelocity(baseVelocity: velocityWithDynamics, noteCount: activeNotesInStep.count)

                switch step.type {
                case .rest:
                    break
                case .arpeggio:
                    let arpeggioStepDuration = singleStepDurationSeconds / Double(activeNotesInStep.count)
                    let sortedNotes = activeNotesInStep.sorted { $0.stringIndex > $1.stringIndex }
                    for (noteIndex, noteItem) in sortedNotes.enumerated() {
                        let noteStartTimeOffset = Double(noteIndex) * arpeggioStepDuration
                        eventIDs.append(contentsOf: self.scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: velocityWithDynamics, channel: channel, scheduledUptime: scheduledUptime + stepStartTimeOffset + noteStartTimeOffset, durationSeconds: totalDuration))
                    }
                case .strum:
                    let strumDelay = self.strumDelayInSeconds(for: step.strumSpeed)
                    let sortedNotes = activeNotesInStep.sorted { step.strumDirection == .down ? $0.stringIndex > $1.stringIndex : $0.stringIndex < $1.stringIndex }
                    for (noteIndex, noteItem) in sortedNotes.enumerated() {
                        let noteStartTimeOffset = Double(noteIndex) * strumDelay
                        eventIDs.append(contentsOf: self.scheduleNote(note: noteItem.note, stringIndex: noteItem.stringIndex, velocity: adaptiveVelocity, channel: channel, scheduledUptime: scheduledUptime + stepStartTimeOffset + noteStartTimeOffset, durationSeconds: totalDuration))
                    }
                }
            }
            completion(eventIDs)
            
            self.workItemsLock.lock()
            self.scheduledWorkItems.removeValue(forKey: workItemID)
            self.workItemsLock.unlock()
        }
        
        workItemsLock.lock()
        scheduledWorkItems[workItemID] = workItem
        workItemsLock.unlock()

        schedulingQueue.asyncAfter(deadline: .now() + (delay > 0 ? delay : 0), execute: workItem)
    }
    
    private func scheduleNote(note: UInt8, stringIndex: Int, velocity: UInt8, channel: UInt8, scheduledUptime: TimeInterval, durationSeconds: TimeInterval) -> [UUID] {
        notesLock.lock()
        defer { notesLock.unlock() }

        var eventIDs: [UUID] = []
        let scheduledUptimeMs = scheduledUptime * 1000.0

        if let previousNote = self.stringNotes[stringIndex] {
            if let scheduledOffId = self.playingNotes[previousNote] {
                self.midiManager.cancelScheduledEvent(id: scheduledOffId)
                self.playingNotes.removeValue(forKey: previousNote)
            }
            self.midiManager.sendNoteOff(note: previousNote, velocity: 0, channel: channel)
        }

        let onId = self.midiManager.scheduleNoteOn(note: note, velocity: velocity, channel: channel, scheduledUptimeMs: scheduledUptimeMs)
        self.stringNotes[stringIndex] = note
        eventIDs.append(onId)

        let scheduledNoteOffUptimeMs = scheduledUptimeMs + (durationSeconds * 1000.0)
        let offId = self.midiManager.scheduleNoteOff(note: note, velocity: 0, channel: channel, scheduledUptimeMs: scheduledNoteOffUptimeMs)
        
        self.playingNotes[note] = offId
        eventIDs.append(offId)
        return eventIDs
    }
    
    private func stopSilentStrings(newChordMidiNotes: [Int], channel: UInt8) {
        notesLock.lock()
        defer { notesLock.unlock() }

        for (stringIndex, note) in stringNotes {
            if newChordMidiNotes[stringIndex] == -1 {
                if let scheduledOffId = playingNotes[note] {
                    midiManager.cancelScheduledEvent(id: scheduledOffId)
                    playingNotes.removeValue(forKey: note)
                }
                midiManager.sendNoteOff(note: note, velocity: 0, channel: channel)
                stringNotes.removeValue(forKey: stringIndex)
            }
        }
    }
    
    private func updateCurrentlyPlayingUI(chordName: String) {
        DispatchQueue.main.async {
            self.appData.currentlyPlayingChordName = chordName
        }
    }

    private func strumDelayInSeconds(for speed: StrumSpeed) -> TimeInterval {
        switch speed {
        case .fast: return 0.01
        case .medium: return 0.025
        case .slow: return 0.05
        }
    }
    
    private func calculateAdaptiveVelocity(baseVelocity: UInt8, noteCount: Int) -> UInt8 {
        guard noteCount > 1 else { return baseVelocity }
        let scalingFactor: Double = 1.2
        let reductionFactor = 1.0 / sqrt(Double(noteCount))
        let adaptiveVelocity = Double(baseVelocity) * reductionFactor * scalingFactor
        let clampedVelocity = max(1, min(127, Int(round(adaptiveVelocity))))
        return UInt8(clampedVelocity)
    }
}

class MusicTheory {
    static let standardGuitarTuning = [64, 59, 55, 50, 45, 40] // EADGBe (index 0 is high E)
    static let KEY_CYCLE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
}