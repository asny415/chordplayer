import Foundation
import Combine

class Metronome: ObservableObject {
    @Published var tempo: Double = 120.0
    @Published var timeSignatureNumerator: Int = 4
    @Published var timeSignatureDenominator: Int = 4

    private var timer: Timer?
    private var beatCount: Int = 0
    private var midiManager: MidiManager
    @Published var isPlaying: Bool = false

    init(midiManager: MidiManager) {
        self.midiManager = midiManager
    }

    func start() {
        stop()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
        let interval = 60.0 / tempo
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.beatCount += 1
            let clickNote: UInt8 = (self.beatCount - 1) % self.timeSignatureNumerator == 0 ? 76 : 75
            self.midiManager.sendNoteOn(note: clickNote, velocity: 100, channel: 9)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.midiManager.sendNoteOff(note: clickNote, velocity: 0, channel: 9)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        beatCount = 0
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}