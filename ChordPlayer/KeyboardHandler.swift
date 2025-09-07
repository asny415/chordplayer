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

    // Allow UI to temporarily pause/resume the shared event monitor so UI-level
    // capture flows can get the raw key events without being intercepted.
    func pauseEventMonitoring() {
        DispatchQueue.main.async {
            if let monitor = self.eventMonitor {
                NSEvent.removeMonitor(monitor)
                self.eventMonitor = nil
            }
        }
    }

    func resumeEventMonitoring() {
        DispatchQueue.main.async {
            if self.eventMonitor == nil {
                self.setupEventMonitor()
            }
        }
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
        guard let charactersRaw = event.charactersIgnoringModifiers else { return }
        let characters = charactersRaw.lowercased()
        let flags = event.modifierFlags

        // Global UI shortcuts (priority)
        // Tempo up/down: arrow keys
        if event.keyCode == 126 { // Up arrow
            appData.performanceConfig.tempo = min(240, appData.performanceConfig.tempo + 5)
            PresetManager.shared.scheduleAutoSave()
            return
        } else if event.keyCode == 125 { // Down arrow
            appData.performanceConfig.tempo = max(40, appData.performanceConfig.tempo - 5)
            PresetManager.shared.scheduleAutoSave()
            return
        }

        // Quantize toggle: 'q'
        if characters == "q" && !flags.contains(.command) {
            let current = QuantizationMode(rawValue: appData.performanceConfig.quantize ?? "NONE") ?? .none
            let all = QuantizationMode.allCases
            if let idx = all.firstIndex(of: current) {
                let next = all[(idx + 1) % all.count]
                appData.performanceConfig.quantize = next.rawValue
                PresetManager.shared.scheduleAutoSave()
            } else if let first = all.first {
                appData.performanceConfig.quantize = first.rawValue
                PresetManager.shared.scheduleAutoSave()
            }
            return
        }

        // Time signature toggle: 't'
        if characters == "t" && !flags.contains(.command) {
            let options = appData.TIME_SIGNATURE_CYCLE
            if let idx = options.firstIndex(of: appData.performanceConfig.timeSignature) {
                let next = options[(idx + 1) % options.count]
                appData.performanceConfig.timeSignature = next
                PresetManager.shared.scheduleAutoSave()
            } else if let first = options.first {
                appData.performanceConfig.timeSignature = first
                PresetManager.shared.scheduleAutoSave()
            }
            return
        }

        // Key cycling: '-' previous, '=' next
        if (characters == "-" || characters == "=") && !flags.contains(.command) {
            let cycle = appData.KEY_CYCLE
            guard !cycle.isEmpty else { return }
            if let idx = cycle.firstIndex(of: appData.performanceConfig.key) {
                let nextIdx: Int
                if characters == "=" {
                    nextIdx = (idx + 1) % cycle.count
                } else {
                    nextIdx = (idx - 1 + cycle.count) % cycle.count
                }
                appData.performanceConfig.key = cycle[nextIdx]
                PresetManager.shared.scheduleAutoSave()
            } else {
                appData.performanceConfig.key = (characters == "=") ? cycle.first! : cycle.last!
                PresetManager.shared.scheduleAutoSave()
            }
            return
        }

        // Command shortcuts (e.g., Cmd+number) handled separately
        if flags.contains(.command) {
            handleCommandShortcuts(characters: characters)
            return
        }

        // Numeric shortcuts (1-9)
        if let number = Int(characters), number >= 1 && number <= 9 {
            handleNumericShortcuts(number: number)
            return
        }

        // Space / simple letter actions
        if event.keyCode == 49 { // Space bar
            if let firstChord = appData.performanceConfig.chords.first {
                playChord(chordName: firstChord)
            }
            return
        }

        if characters == "p" {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            } else {
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
            }
            return
        }

        // If none of the above, try chord shortcuts
        if let shortcut = Shortcut.from(event: event) {
            if let chord = resolveChordForShortcut(shortcut) {
                playChord(chordName: chord)
                return
            }
        }
    }

    // Resolve a shortcut to a chord name.
    private func resolveChordForShortcut(_ shortcut: Shortcut) -> String? {
        // 1. Check current preset custom mappings
        if let preset = PresetManager.shared.currentPreset {
            for (chord, s) in preset.chordShortcuts {
                if s == shortcut { return chord }
            }
        }

        // 2. Fallback to default rule: Letter_Major -> lowercase letter (no shift) ; Letter_Minor -> Shift+Letter
        guard let chords = appData.performanceConfig.chords as [String]? else { return nil }
        for chord in chords {
            let parts = chord.split(separator: "_")
            if parts.count >= 2 {
                let letter = String(parts[0])
                let quality = String(parts[1])
                if letter.count == 1 {
                    let upper = letter.uppercased()
                    if quality == "Major" && shortcut.modifiersShift == false && shortcut.key == upper {
                        return chord
                    }
                    if quality == "Minor" && shortcut.modifiersShift == true && shortcut.key == upper {
                        return chord
                    }
                }
            }
        }

        return nil
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

    // Public wrapper so UI code can request a chord to be played.
    func playChordByName(_ chordName: String) {
        playChord(chordName: chordName)
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