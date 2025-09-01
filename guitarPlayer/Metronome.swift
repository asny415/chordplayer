import Foundation
import Combine

class Metronome: ObservableObject {
    @Published var tempo: Double = 120.0 // BPM
    @Published var timeSignatureNumerator: Int = 4 // e.g., 4 for 4/4
    @Published var timeSignatureDenominator: Int = 4 // e.g., 4 for 4/4

    private var timer: Timer?
    private var beatCount: Int = 0
    private var midiManager: MidiManager // Dependency injection

    init(midiManager: MidiManager) {
        self.midiManager = midiManager
    }

    func start() {
        stop() // Ensure any existing timer is stopped
        let interval = 60.0 / tempo // Seconds per beat
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.beatCount += 1
            // Play a click sound (e.g., MIDI note 76 for high wood block, 75 for low wood block)
            let clickNote: UInt8 = (self.beatCount - 1) % self.timeSignatureNumerator == 0 ? 76 : 75 // Accent first beat
            self.midiManager.sendNoteOn(note: clickNote, velocity: 100, channel: 9) // Channel 9 for percussion
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // Short duration
                self.midiManager.sendNoteOff(note: clickNote, velocity: 0, channel: 9)
            }
            // Here, we would also trigger any scheduled musical events
            // For now, just the click
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        beatCount = 0
    }

    // Function to calculate duration of a musical note (e.g., "1/4" note) in seconds
    func duration(forNoteValue noteValue: StringOrDouble) -> TimeInterval? {
        let _ = Double(timeSignatureNumerator)
        let beatUnit = Double(timeSignatureDenominator) // e.g., 4 for quarter note

        switch noteValue {
        case .string(let s):
            if let parsedFraction = MusicTheory.parseDelay(delayString: s) {
                // If it's a fraction like "1/4", it represents a fraction of a whole note
                // A whole note (1/1) is 4 beats in 4/4 time.
                // So, a "1/4" note is 1 beat.
                // A "1/8" note is 0.5 beats.
                // The `parsedFraction` is relative to a whole note.
                // We need to convert it to beats based on the time signature's beat unit.
                // For example, in 4/4, a 1/4 note is 1 beat. In 3/8, a 1/8 note is 1 beat.
                // The `parsedFraction` is `numerator / denominator` of a whole note.
                // A beat is `1 / beatUnit` of a whole note.
                // So, `parsedFraction / (1 / beatUnit)` gives us the number of beats.
                let numberOfBeats = parsedFraction * beatUnit
                return numberOfBeats * (60.0 / tempo) // Convert beats to seconds
            } else {
                // If it's a string that's not a fraction, treat as milliseconds (like in original JS)
                if let ms = Double(s) {
                    return ms / 1000.0 // Convert milliseconds to seconds
                }
            }
        case .double(let d):
            // If it's a number, treat as milliseconds (like in original JS)
            return d / 1000.0 // Convert milliseconds to seconds
        case .int(let i):
            // If it's an integer, treat as milliseconds (like in original JS)
            return Double(i) / 1000.0 // Convert milliseconds to seconds
        }
        return nil
    }
}
