import Foundation
import Combine

class DrumPlayer: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var appData: AppData // To access drum pattern library

    private var currentPatternTimer: Timer?
    private var currentPatternEvents: [DrumPatternEvent]?
    private var currentPatternIndex: Int = 0

    init(midiManager: MidiManager, metronome: Metronome, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.appData = appData
    }

    func playPattern(patternName: String, velocity: UInt8 = 100) {
        stop() // Stop any existing pattern

        guard let pattern = appData.drumPatternLibrary?[patternName] else {
            print("[DrumPlayer] Pattern definition for \(patternName) not found.")
            return
        }
        self.currentPatternEvents = pattern
        self.currentPatternIndex = 0

        scheduleNextDrumEvent(velocity: velocity)
    }

    private func scheduleNextDrumEvent(velocity: UInt8) {
        guard let patternEvents = currentPatternEvents, !patternEvents.isEmpty else {
            stop()
            return
        }

        let event = patternEvents[currentPatternIndex]

        // Calculate the actual delay in seconds
        guard let eventDelay = metronome.duration(forNoteValue: .string(event.delay)) else {
            print("[DrumPlayer] Could not parse delay for drum event: \(event.delay)")
            stop()
            return
        }

        // Schedule note-on for each note in the event
        for note in event.notes {
            midiManager.sendNoteOn(note: UInt8(note), velocity: velocity, channel: 9) // Drum channel is typically 9 (10 in MIDI spec)
            // Send note-off almost immediately for percussion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.midiManager.sendNoteOff(note: UInt8(note), velocity: 0, channel: 9)
            }
        }

        // Schedule the next event
        currentPatternIndex = (currentPatternIndex + 1) % patternEvents.count
        currentPatternTimer = Timer.scheduledTimer(withTimeInterval: eventDelay, repeats: false) { [weak self] _ in
            self?.scheduleNextDrumEvent(velocity: velocity)
        }
    }

    func stop() {
        currentPatternTimer?.invalidate()
        currentPatternTimer = nil
        currentPatternEvents = nil
        currentPatternIndex = 0
        midiManager.sendPanic() // Send panic to ensure all drum notes are off
    }
}
