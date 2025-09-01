import Foundation
import SwiftUI
import AppKit

class KeyboardHandler: ObservableObject {
    private var midiManager: MidiManager
    private var metronome: Metronome
    private var guitarPlayer: GuitarPlayer
    private var drumPlayer: DrumPlayer
    private var appData: AppData

    // State for keyboard shortcuts that modify global state
    @Published var currentKeyIndex: Int
    @Published var currentTempo: Double
    @Published var currentTimeSignature: String
    @Published var quantizationMode: String
    @Published var currentGroupIndex: Int

    private var eventMonitor: Any?

    init(midiManager: MidiManager, metronome: Metronome, guitarPlayer: GuitarPlayer, drumPlayer: DrumPlayer, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.guitarPlayer = guitarPlayer
        self.drumPlayer = drumPlayer
        self.appData = appData

        // Initialize published properties from appData or default values
        _currentTempo = Published(initialValue: appData.performanceConfig.tempo)
        _currentTimeSignature = Published(initialValue: appData.performanceConfig.timeSignature)
        _quantizationMode = Published(initialValue: appData.performanceConfig.quantize ?? "MEASURE")
        _currentGroupIndex = Published(initialValue: 0) // Assuming initial group index is 0

        // Find initialKeyIndex based on performanceConfig.key
        let initialKey = appData.performanceConfig.key
        if let index = appData.KEY_CYCLE.firstIndex(of: initialKey) {
            _currentKeyIndex = Published(initialValue: index)
        } else {
            _currentKeyIndex = Published(initialValue: 0) // Default to 0 if not found
        }

        setupEventMonitor()
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event: event)
            return event // Pass the event on
        }
    }

    func handleKeyEvent(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }

        let isControlDown = event.modifierFlags.contains(.control)
        let isShiftDown = event.modifierFlags.contains(.shift)
        let isOptionDown = event.modifierFlags.contains(.option)
        let isCommandDown = event.modifierFlags.contains(.command)

        // Handle Ctrl+C for cleanup (exit)
        if isControlDown && characters == "c" {
            print("Ctrl+C pressed. Exiting.")
            NSApplication.shared.terminate(nil)
            return
        }

        // Get the key name for comparison with JS logic
        let keyName: String
        switch event.keyCode {
        case 126: keyName = "up" // Up arrow
        case 125: keyName = "down" // Down arrow
        case 24: keyName = "equal" // =
        case 27: keyName = "minus" // -
        case 49: keyName = "space" // Spacebar
        case 18: keyName = "1"
        case 19: keyName = "2"
        case 20: keyName = "3"
        case 21: keyName = "4"
        case 23: keyName = "5"
        case 22: keyName = "6"
        case 26: keyName = "7"
        case 28: keyName = "8"
        case 25: keyName = "9"
        case 17: keyName = "t"
        case 12: keyName = "q"
        default: keyName = characters.lowercased()
        }

        // Quantization Toggle
        let quantizeToggleKey = appData.performanceConfig.quantizeToggleKey ?? "q"
        if keyName == quantizeToggleKey {
            let modes = [QuantizationMode.none.rawValue, QuantizationMode.measure.rawValue, QuantizationMode.halfMeasure.rawValue] // Directly use enum raw values
            if let currentIndex = modes.firstIndex(of: quantizationMode) {
                quantizationMode = modes[(currentIndex + 1) % modes.count]
            } else {
                quantizationMode = modes.first ?? "MEASURE"
            }
            print("\nQuantization mode: \(quantizationMode)")
            return
        }

        // Drum controls
        if let drumSettings = appData.performanceConfig.drumSettings {
            if keyName == drumSettings.playKey {
                let drumPatternToPlay = appData.DRUM_PATTERN_MAP[currentTimeSignature] ?? drumSettings.defaultPattern
                drumPlayer.playPattern(patternName: drumPatternToPlay) // Corrected method call
                return
            }
            if keyName == drumSettings.stopKey {
                drumPlayer.stop() // Corrected method call
                return
            }
        }

        // Key transposition
        if keyName == "equal" || keyName == "plus" || characters == "=" {
            currentKeyIndex = (currentKeyIndex + 1) % appData.KEY_CYCLE.count
            print("\nKey transposed UP to: \(appData.KEY_CYCLE[currentKeyIndex])")
            return
        }
        if keyName == "minus" || keyName == "underscore" || characters == "-" {
            currentKeyIndex = (currentKeyIndex - 1 + appData.KEY_CYCLE.count) % appData.KEY_CYCLE.count
            print("\nKey transposed DOWN to: \(appData.KEY_CYCLE[currentKeyIndex])")
            return
        }

        // Tempo controls
        if keyName == "up" {
            currentTempo = min(240, currentTempo + 5)
            print("\nTempo increased to: \(currentTempo) BPM")
            return
        }
        if keyName == "down" {
            currentTempo = max(60, currentTempo - 5)
            print("\nTempo decreased to: \(currentTempo) BPM")
            return
        }

        // Time Signature controls
        if keyName == "t" {
            if let currentIndex = appData.TIME_SIGNATURE_CYCLE.firstIndex(of: currentTimeSignature) {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE[(currentIndex + 1) % appData.TIME_SIGNATURE_CYCLE.count]
            } else {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE.first ?? "4/4"
            }
            print("\nTime Signature changed to: \(currentTimeSignature)")
            return
        }

        // Pattern Group change (1-9)
        if let groupIndex = Int(keyName), groupIndex >= 1 && groupIndex <= 9 {
            let actualGroupIndex = groupIndex - 1
            if appData.performanceConfig.patternGroups.indices.contains(actualGroupIndex) {
                currentGroupIndex = actualGroupIndex
                print("\nPattern Group changed to: \(appData.performanceConfig.patternGroups[currentGroupIndex].name)")
                return
            }
        }

        // Chord playing
        var chordName: String? = nil

        if let mappedChord = appData.performanceConfig.keyMap[keyName] {
            chordName = mappedChord
        } else {
            let simulatedKey = JSKey(name: characters, meta: isCommandDown, alt: isOptionDown, ctrl: isControlDown, shift: isShiftDown)
            chordName = MusicTheory.getChordFromDefaultMapping(key: simulatedKey)
        }

        if let chord = chordName {
            let currentGroup = appData.performanceConfig.patternGroups[currentGroupIndex]
            // Resolve pattern name for this chord/group.
            // Note: `currentGroup.patterns` has type [String: String?], so accessing
            // a key returns String?? (optional optional). The JS code treats null
            // (explicit null) as falsy and falls back to __default__ / DEFAULT_PATTERNS.
            // To mirror that behaviour we must treat either a missing key or an
            // explicit null value as "no explicit pattern" and continue fallback.

            var resolvedPatternName: String? = nil

            // Check explicit chord mapping in group. If key exists and value is non-nil, use it.
            if let valueOptional = currentGroup.patterns[chord] {
                if let value = valueOptional {
                    resolvedPatternName = value
                } else {
                    // explicit null -> treat as absent (fallthrough to __default__)
                }
            }

            // If still not resolved, check group's __default__ (again treat explicit null as absent)
            if resolvedPatternName == nil {
                if let defaultOptional = currentGroup.patterns["__default__"] {
                    if let defaultValue = defaultOptional {
                        resolvedPatternName = defaultValue
                    }
                }
            }

            // If still not resolved, consult DEFAULT_PATTERNS mapping (same logic as JS fallback)
            if resolvedPatternName == nil {
                let chordType = MusicTheory.getChordType(chordName: chord)
                let section = MusicTheory.getSectionName(groupIndex: currentGroupIndex)
                let rootString = MusicTheory.getChordRootString(chordName: chord, chordLibrary: appData.chordLibrary)

                let defaultPatternName = appData.DEFAULT_PATTERNS[chordType]?[currentTimeSignature]?[section]?[rootString]

                if let dpn = defaultPatternName {
                    // concise log: which default pattern will be used
                    print("Key '\(characters)' -> chord '\(chord)' -> using default pattern '\(dpn)' (root: \(rootString), section: \(section), timeSig: \(currentTimeSignature))")
                    resolvedPatternName = dpn
                } else {
                    print("Key '\(characters)' -> chord '\(chord)' -> no default pattern available (root: \(rootString), section: \(section), timeSig: \(currentTimeSignature)).")
                    return
                }
            }

            if let patternName = resolvedPatternName {
                let finalPattern = appData.patternLibrary?[patternName]

                let exists = (finalPattern != nil)
                print("patternLibrary contains '\(patternName)'? \(exists)")

                if let fp = finalPattern {
                    // Convert duration (ms in JS CONFIG) to seconds for Swift timers
                    let durationSeconds = TimeInterval(appData.CONFIG.duration) / 1000.0
                    let keyString = appData.KEY_CYCLE[currentKeyIndex]
                    guitarPlayer.playChord(
                        chordName: chord,
                        pattern: fp,
                        tempo: currentTempo,
                        key: keyString,
                        velocity: UInt8(appData.CONFIG.velocity),
                        duration: durationSeconds
                    )
                } else {
                    print("\nError: Could not resolve pattern data for \(chord).")
                }
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// Helper struct to simulate the 'key' object from Node.js readline
struct JSKey {
    let name: String
    let meta: Bool // Corresponds to Command key on macOS
    let alt: Bool // Corresponds to Option key on macOS
    let ctrl: Bool // Corresponds to Control key on macOS
    let shift: Bool
}