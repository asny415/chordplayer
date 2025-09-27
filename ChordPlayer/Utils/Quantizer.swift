import Foundation

// 1. Defines the requirements for an object that can be quantized.
protocol Quantizable {
    var midiSequencer: MIDISequencer { get }
    var appData: AppData { get }
}

// 2. Provides the shared implementation for any class that conforms to Quantizable.
extension Quantizable {
    func nextQuantizationTime(for mode: QuantizationMode) -> Double {
        let now = ProcessInfo.processInfo.systemUptime // Time in seconds
        if !midiSequencer.isPlaying || mode == .none {
            return now
        }

        let bpm = appData.preset?.bpm ?? 120.0
        guard bpm > 0 else { return now }
        
        let secondsPerBeat = 60.0 / bpm
        
        // Calculate the effective start time of the sequence from the sequencer's state
        let currentBeat = midiSequencer.currentTimeInBeats
        let elapsedTimeInSeconds = currentBeat * secondsPerBeat
        let startTime = now - elapsedTimeInSeconds

        let beatsPerMeasure = Double(appData.preset?.timeSignature.beatsPerMeasure ?? 4)
        let measureDurationSeconds = beatsPerMeasure * secondsPerBeat
        let halfMeasureDurationSeconds = measureDurationSeconds / 2.0

        let elapsedTimeSinceStart = now - startTime
        let currentMeasureIndex = floor(elapsedTimeSinceStart / measureDurationSeconds)
        let currentMeasureStartTime = startTime + (currentMeasureIndex * measureDurationSeconds)

        switch mode {
        case .measure:
            return currentMeasureStartTime + measureDurationSeconds
        case .halfMeasure:
            let halfMeasures = floor((now - currentMeasureStartTime) / halfMeasureDurationSeconds)
            return currentMeasureStartTime + (halfMeasures + 1) * halfMeasureDurationSeconds
        case .none:
            return now
        }
    }
}