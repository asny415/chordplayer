import Foundation
import SwiftUI
import AppKit
import Combine

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
    private var cancellables = Set<AnyCancellable>()

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
        // Observe programmatic changes to timeSignature (e.g., from UI picker)
        $currentTimeSignature
            .sink { [weak self] new in
                guard let self = self else { return }
                // Update metronome and persist to appData when time signature changes
                let parts = new.split(separator: "/").map(String.init)
                if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                    DispatchQueue.main.async {
                        self.metronome.timeSignatureNumerator = num
                        self.metronome.timeSignatureDenominator = den
                    }
                }
                self.appData.performanceConfig.timeSignature = new
                print("[KeyboardHandler] timeSignature changed -> \(new)")
            }
            .store(in: &cancellables)
    }

    private func setupEventMonitor() {
        // Ensure the monitor is installed on the main thread.
        // Install synchronously when possible so the first key press is not missed during initialization.
        let installer = {
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.handleKeyEvent(event: event)
                return event
            }
        }

        if Thread.isMainThread {
            installer()
        } else {
            DispatchQueue.main.sync {
                installer()
            }
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

        // Debug: log certain keys to help diagnose missing shortcut handling
        let debugKeys: Set<String> = ["t", "p", "o", "q", "=", "-", "up", "down"]
        if debugKeys.contains(keyName) {
            print("[KeyboardHandler] key event: keyName='\(keyName)' chars='\(characters)' modifiers='\(event.modifierFlags)' keyCode=\(event.keyCode)")
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
            // propagate quantization setting to appData so UI and other subsystems stay in sync
            appData.performanceConfig.quantize = quantizationMode
            return
        }

        // Drum controls
        if let drumSettings = appData.performanceConfig.drumSettings {
            if keyName == drumSettings.playKey {
                // Toggle behavior: start if stopped, stop if playing
                if drumPlayer.isPlaying {
                    drumPlayer.stop()
                } else {
                    let drumPatternToPlay = appData.DRUM_PATTERN_MAP[currentTimeSignature] ?? drumSettings.defaultPattern
                    // Match JS DrumPlayer defaults: velocity 100, duration 200ms
                    drumPlayer.playPattern(patternName: drumPatternToPlay, tempo: currentTempo, timeSignature: currentTimeSignature, velocity: 100, durationMs: 200)
                }
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
            // propagate key change to global config so UI reflects it
            appData.performanceConfig.key = appData.KEY_CYCLE[currentKeyIndex]
            return
        }
        if keyName == "minus" || keyName == "underscore" || characters == "-" {
            currentKeyIndex = (currentKeyIndex - 1 + appData.KEY_CYCLE.count) % appData.KEY_CYCLE.count
            appData.performanceConfig.key = appData.KEY_CYCLE[currentKeyIndex]
            return
        }

        // Tempo controls
        if keyName == "up" {
            currentTempo = min(240, currentTempo + 5)
            // update metronome so tempo UI and timing are immediately effective
            metronome.tempo = currentTempo
            return
        }
        if keyName == "down" {
            currentTempo = max(60, currentTempo - 5)
            metronome.tempo = currentTempo
            return
        }

        // Time Signature controls
        if keyName == "t" {
            if let currentIndex = appData.TIME_SIGNATURE_CYCLE.firstIndex(of: currentTimeSignature) {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE[(currentIndex + 1) % appData.TIME_SIGNATURE_CYCLE.count]
            } else {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE.first ?? "4/4"
            }
        // propagate to metronome (split N/D) and persist to appData
            let parts = currentTimeSignature.split(separator: "/").map(String.init)
            if parts.count == 2 {
                if let num = Int(parts[0]), let den = Int(parts[1]) {
                    metronome.timeSignatureNumerator = num
                    metronome.timeSignatureDenominator = den
                    // persist the timeSignature to appData so UI and saved config stay in sync
                    appData.performanceConfig.timeSignature = currentTimeSignature
                }
            }
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
                    // Prepare play parameters
                    let durationSeconds = TimeInterval(appData.CONFIG.duration) / 1000.0
                    let keyString = appData.KEY_CYCLE[currentKeyIndex]
                    let quantMode = quantizationMode

                    // Quantization handling similar to JS scheduleChord
                    if quantMode == QuantizationMode.none.rawValue {
                        guitarPlayer.playChord(chordName: chord, pattern: fp, tempo: currentTempo, key: keyString, velocity: UInt8(appData.CONFIG.velocity), duration: durationSeconds)
                    } else {
                        // Need drum clock info
                        let clock = drumPlayer.clockInfo
                        if !clock.isPlaying || clock.loopDuration <= 0 {
                            // No clock available: play immediately
                            guitarPlayer.playChord(chordName: chord, pattern: fp, tempo: currentTempo, key: keyString, velocity: UInt8(appData.CONFIG.velocity), duration: durationSeconds)
                        } else {
                            var division = 1.0
                            if quantMode == QuantizationMode.halfMeasure.rawValue {
                                division = 2.0
                            }
                            let quantizationInterval = clock.loopDuration / division
                            // Use monotonic uptime (ms) so both drum and guitar use same baseline
                            let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
                            let loopElapsedTime = fmod(nowUptimeMs - clock.startTime, clock.loopDuration)
                            let currentInterval = floor(loopElapsedTime / quantizationInterval)
                            let timeToNextIntervalStart = ((currentInterval + 1.0) * quantizationInterval) - loopElapsedTime
                            let QUANTIZATION_WINDOW_PERCENT = 0.5
                            let quantizationWindow = quantizationInterval * QUANTIZATION_WINDOW_PERCENT

                            if timeToNextIntervalStart <= quantizationWindow {
                                // schedule delayed play to align with next interval start
                                let delaySeconds = timeToNextIntervalStart / 1000.0
                                // Use guitar's scheduling queue to avoid creating new global queue tasks
                                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                                    Thread.current.threadPriority = 1.0
                                    guard let self = self else { return }
                                    self.guitarPlayer.playChord(chordName: chord, pattern: fp, tempo: self.currentTempo, key: keyString, velocity: UInt8(self.appData.CONFIG.velocity), duration: durationSeconds)
                                }
                            } else {
                                // Outside window: ignore press (same as JS)
                                return
                            }
                        }
                    }
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