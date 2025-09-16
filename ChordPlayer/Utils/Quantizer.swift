
import Foundation

// 1. Defines the requirements for an object that can be quantized.
protocol Quantizable {
    var drumPlayer: DrumPlayer { get }
    var appData: AppData { get }
}

// 2. Provides the shared implementation for any class that conforms to Quantizable.
extension Quantizable {
    func nextQuantizationTime(for mode: QuantizationMode) -> Double {
        let now = ProcessInfo.processInfo.systemUptime * 1000.0
        if !drumPlayer.isPlaying || mode == .none {
            return now
        }

        let beatDurationMs = (60.0 / (appData.preset?.bpm ?? 120.0)) * 1000.0
        let beatsPerMeasure = appData.preset?.timeSignature.beatsPerMeasure ?? 4
        let measureDurationMs = beatDurationMs * Double(beatsPerMeasure)
        let halfMeasureDurationMs = measureDurationMs / 2.0

        let currentMeasureIndex = floor((now - drumPlayer.startTimeMs) / measureDurationMs)
        let currentMeasureStartTime = drumPlayer.startTimeMs + (currentMeasureIndex * measureDurationMs)

        switch mode {
        case .measure:
            return currentMeasureStartTime + measureDurationMs
        case .halfMeasure:
            let halfMeasures = floor((now - currentMeasureStartTime) / halfMeasureDurationMs)
            return currentMeasureStartTime + (halfMeasures + 1) * halfMeasureDurationMs
        case .none:
            return now
        }
    }
}
