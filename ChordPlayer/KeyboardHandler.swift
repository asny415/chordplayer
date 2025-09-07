import Foundation
import SwiftUI
import AppKit
import Combine

class KeyboardHandler: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var chordPlayer: ChordPlayer
    private var drumPlayer: DrumPlayer
    private var appData: AppData

    @Published var lastPlayedChord: String? = nil
    @Published var isTextInputActive: Bool = false

    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager, metronome: Metronome, chordPlayer: ChordPlayer, drumPlayer: DrumPlayer, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.chordPlayer = chordPlayer
        self.drumPlayer = drumPlayer
        self.appData = appData

        setupEventMonitor()

        appData.$performanceConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.updateWithNewConfig(newConfig)
            }
            .store(in: &cancellables)
    }

    func updateWithNewConfig(_ config: PerformanceConfig) {
        metronome.update(from: config)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            if let responder = NSApp.keyWindow?.firstResponder, 
               let view = responder as? NSView, view.isDescendant(of: NSApp.keyWindow?.contentView ?? NSView()) {
                let className = String(describing: type(of: responder))
                if className.contains("NSText") { return event }
            }

            if self.isTextInputActive { return event }

            self.handleKeyEvent(event: event)
            return nil
        }
    }

    private func handleKeyEvent(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return }
        let flags = event.modifierFlags

        if flags.contains(.command) {
            handleCommandShortcuts(characters: characters)
        } else if let number = Int(characters), number >= 1 && number <= 9 {
            handleNumericShortcuts(number: number)
        } else {
            if event.keyCode == 49 { // Space bar
                if let firstChord = appData.performanceConfig.chords.first {
                    playChord(chordName: firstChord)
                }
            } else if characters == "p" {
                if drumPlayer.isPlaying {
                    drumPlayer.stop()
                } else {
                    drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
                }
            }
        }
    }

    private func handleCommandShortcuts(characters: String) {
        if let number = Int(characters), number >= 1 && number <= 9 {
            let index = number - 1
            if appData.performanceConfig.selectedDrumPatterns.indices.contains(index) {
                let patternId = appData.performanceConfig.selectedDrumPatterns[index]
                appData.performanceConfig.activeDrumPatternId = patternId
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
            }
        }
    }

    private func handleNumericShortcuts(number: Int) {
        let index = number - 1
        if appData.performanceConfig.selectedPlayingPatterns.indices.contains(index) {
            let patternId = appData.performanceConfig.selectedPlayingPatterns[index]
            appData.performanceConfig.activePlayingPatternId = patternId
        }
    }

    private func playChord(chordName: String) {
        guard let playingPatternId = appData.performanceConfig.activePlayingPatternId else { return }
        let timeSignature = appData.performanceConfig.timeSignature
        guard let pattern = appData.patternLibrary?[timeSignature]?.first(where: { $0.id == playingPatternId }) else {
            print("Error: Could not resolve playing pattern.")
            return
        }

        let config = appData.performanceConfig
        let appConfig = appData.CONFIG

        chordPlayer.playChord(
            chordName: chordName, 
            pattern: pattern, 
            tempo: config.tempo, 
            key: config.key, 
            velocity: UInt8(appConfig.velocity), 
            duration: TimeInterval(appConfig.duration) / 1000.0,
            quantizationMode: QuantizationMode(rawValue: config.quantize ?? "NONE") ?? .none,
            drumClockInfo: drumPlayer.clockInfo
        )
        
        DispatchQueue.main.async {
            self.lastPlayedChord = chordName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.lastPlayedChord = nil
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension Metronome {
    func update(from config: PerformanceConfig) {
        self.tempo = config.tempo
        let parts = config.timeSignature.split(separator: "/").map(String.init)
        if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
            self.timeSignatureNumerator = num
            self.timeSignatureDenominator = den
        }
    }
}