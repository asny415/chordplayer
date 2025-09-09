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


            // If the current first responder appears to be a text input control
            // that belongs to the key window's view hierarchy, let the event
            // pass through so the control can receive typing.
            if let responder = NSApp.keyWindow?.firstResponder,
               let view = responder as? NSView,
               view.isDescendant(of: NSApp.keyWindow?.contentView ?? NSView()) {

                // Common Cocoa text input classes
                if responder is NSTextView || responder is NSTextField {
                    return event
                }
            }

            // Note: text-input responder checks are handled via firstResponder detection above.

            // Only swallow the event when our handler actually handled it.
            let handled = self.handleKeyEvent(event: event)
            return handled ? nil : event
        }
    }

    // Return true when the event was handled and should be consumed.
    private func handleKeyEvent(event: NSEvent) -> Bool {
        guard let charactersRaw = event.charactersIgnoringModifiers else { return false }
        let characters = charactersRaw.lowercased()
        let flags = event.modifierFlags

        // Global UI shortcuts (priority)
        // Tempo up/down: arrow keys
        if event.keyCode == 126 { // Up arrow
            appData.performanceConfig.tempo = min(240, appData.performanceConfig.tempo + 5)
            PresetManager.shared.scheduleAutoSave()
            return true
        } else if event.keyCode == 125 { // Down arrow
            appData.performanceConfig.tempo = max(40, appData.performanceConfig.tempo - 5)
            PresetManager.shared.scheduleAutoSave()
            return true
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
            return true
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
            return true
        }

        // Key cycling: '-' previous, '=' next
    if (characters == "-" || characters == "=") && !flags.contains(.command) {
            let cycle = appData.KEY_CYCLE
            guard !cycle.isEmpty else { return true }
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
            return true
        }

        // Command shortcuts (e.g., Cmd+number) handled separately
        if flags.contains(.command) {
            return handleCommandShortcuts(characters: characters)
        }

        // Numeric shortcuts (1-9)
        if let number = Int(characters), number >= 1 && number <= 9 {
            return handleNumericShortcuts(number: number)
        }

        // Space / simple letter actions
        if event.keyCode == 49 { // Space bar
            if let firstChord = appData.performanceConfig.chords.first {
                playChord(chordName: firstChord.name)
            }
            return true
        }

        if characters == "p" {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            } else {
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
            }
            return true
        }

        // If none of the above, try chord shortcuts and chord playing pattern associations
        if let shortcut = Shortcut.from(event: event) {
            // 首先检查是否有演奏指法关联
            if let association = PresetManager.shared.findAssociationByShortcut(shortcut) {
                playChordWithAssociation(chordName: association.chordName, association: association)
                return true
            }
            
            // 然后检查普通和弦快捷键
            if let chord = resolveChordForShortcut(shortcut) {
                playChord(chordName: chord)
                return true
            }
        }

        return false
    }

    private func resolveChordForShortcut(_ shortcut: Shortcut) -> String? {
        // 1. Check current preset custom mappings
        if let preset = PresetManager.shared.currentPreset {
            for (chord, s) in preset.chordShortcuts {
                if s == shortcut { return chord }
            }
        }

        // 2. Fallback to default rule: Letter_Major -> lowercase letter (no shift) ; Letter_Minor -> Shift+Letter
        for chordConfig in appData.performanceConfig.chords {
            let chordName = chordConfig.name
            let parts = chordName.split(separator: "_")
            if parts.count >= 2 {
                let letter = String(parts[0])
                let quality = String(parts[1])
                if letter.count == 1 {
                    let upper = letter.uppercased()
                    if quality == "Major" && shortcut.modifiersShift == false && shortcut.key == upper {
                        return chordName
                    }
                    if quality == "Minor" && shortcut.modifiersShift == true && shortcut.key == upper {
                        return chordName
                    }
                }
            }
        }

        return nil
    }

    // Return true when a command-modified shortcut was handled (and should be consumed).
    private func handleCommandShortcuts(characters: String) -> Bool {
        if let number = Int(characters), number >= 1 && number <= 9 {
            let index = number - 1
            if appData.performanceConfig.selectedDrumPatterns.indices.contains(index) {
                let patternId = appData.performanceConfig.selectedDrumPatterns[index]
                appData.performanceConfig.activeDrumPatternId = patternId
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
                return true
            }
        }
        return false
    }

    private func handleNumericShortcuts(number: Int) -> Bool {
        let index = number - 1
        if appData.performanceConfig.selectedPlayingPatterns.indices.contains(index) {
            let patternId = appData.performanceConfig.selectedPlayingPatterns[index]
            appData.performanceConfig.activePlayingPatternId = patternId
            return true
        }
        return false
    }

    private func playChord(chordName: String) {
        guard let playingPatternId = appData.performanceConfig.activePlayingPatternId else { return }
        let timeSignature = appData.performanceConfig.timeSignature
        
        // 查找演奏指法（包括自定义的）
        var pattern: GuitarPattern?
        if let library = appData.patternLibrary?[timeSignature] {
            pattern = library.first(where: { $0.id == playingPatternId })
        }
        if pattern == nil, let customLibrary = CustomPlayingPatternManager.shared.customPlayingPatterns[timeSignature] {
            pattern = customLibrary.first(where: { $0.id == playingPatternId })
        }
        
        guard let foundPattern = pattern else {
            print("Error: Could not resolve playing pattern.")
            return
        }

        let config = appData.performanceConfig
        let appConfig = appData.CONFIG

        chordPlayer.playChord(
            chordName: chordName, 
            pattern: foundPattern, 
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
    
    private func playChordWithAssociation(chordName: String, association: ChordPlayingPatternAssociation) {
        let timeSignature = appData.performanceConfig.timeSignature
        
        // 查找关联的演奏指法（包括自定义的）
        var pattern: GuitarPattern?
        if let library = appData.patternLibrary?[timeSignature] {
            pattern = library.first(where: { $0.id == association.playingPatternId })
        }
        if pattern == nil, let customLibrary = CustomPlayingPatternManager.shared.customPlayingPatterns[timeSignature] {
            pattern = customLibrary.first(where: { $0.id == association.playingPatternId })
        }
        
        guard let foundPattern = pattern else {
            print("Error: Could not resolve associated playing pattern.")
            return
        }

        let config = appData.performanceConfig
        let appConfig = appData.CONFIG

        chordPlayer.playChord(
            chordName: chordName, 
            pattern: foundPattern, 
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
