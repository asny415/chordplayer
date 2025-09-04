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
    @Published var activeChordName: String?
    // When true, global keyboard handler should ignore events (TextField is active)
    @Published var isTextInputActive: Bool = false

    @Published var isCapturingShortcut: Bool = false // NEW STATE
    var targetChordForShortcutCapture: String? = nil // NEW PROPERTY
    var onShortcutCaptured: ((String, String) -> Void)? // NEW CALLBACK

    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var activeChordClearWorkItem: DispatchWorkItem?

    init(midiManager: MidiManager, metronome: Metronome, guitarPlayer: GuitarPlayer, drumPlayer: DrumPlayer, appData: AppData) {
        self.midiManager = midiManager
        self.metronome = metronome
        self.guitarPlayer = guitarPlayer
        self.drumPlayer = drumPlayer
        self.appData = appData

        _currentTempo = Published(initialValue: appData.performanceConfig.tempo)
        _currentTimeSignature = Published(initialValue: appData.performanceConfig.timeSignature)
        _quantizationMode = Published(initialValue: appData.performanceConfig.quantize ?? "MEASURE")
        _currentGroupIndex = Published(initialValue: 0)

        let initialKey = appData.performanceConfig.key
        if let index = appData.KEY_CYCLE.firstIndex(of: initialKey) {
            _currentKeyIndex = Published(initialValue: index)
        } else {
            _currentKeyIndex = Published(initialValue: 0)
        }

        setupEventMonitor()
        $currentTimeSignature
            .sink { [weak self] new in
                guard let self = self else { return }
                let parts = new.split(separator: "/").map(String.init)
                if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                    DispatchQueue.main.async {
                        self.metronome.timeSignatureNumerator = num
                        self.metronome.timeSignatureDenominator = den
                    }
                }
                self.appData.performanceConfig.timeSignature = new
            }
            .store(in: &cancellables)

        $currentTempo
            .sink { [weak self] newTempo in
                self?.appData.performanceConfig.tempo = newTempo
            }
            .store(in: &cancellables)
    }

    func startCapturingShortcut(for chordName: String) {
        isCapturingShortcut = true
        targetChordForShortcutCapture = chordName
        // Optionally, provide visual feedback here, e.g., via a published property
    }

    func stopCapturingShortcut() {
        isCapturingShortcut = false
        targetChordForShortcutCapture = nil
    }
    
    // MARK: - Shortcut Key Formatting
    private func formatShortcutKey(event: NSEvent) -> String {
        guard let characters = event.charactersIgnoringModifiers else { return "" }
        
        let isControlDown = event.modifierFlags.contains(.control)
        let isShiftDown = event.modifierFlags.contains(.shift)
        let isOptionDown = event.modifierFlags.contains(.option)
        let isCommandDown = event.modifierFlags.contains(.command)
        
        // Get the base key name
        let keyName: String
        switch event.keyCode {
        case 126: keyName = "up"
        case 125: keyName = "down"
        case 24: keyName = "equal"
        case 27: keyName = "minus"
        case 49: keyName = "space"
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
        
        // Build modifier string
        var modifiers: [String] = []
        if isCommandDown { modifiers.append("⌘") }
        if isControlDown { modifiers.append("⌃") }
        if isOptionDown { modifiers.append("⌥") }
        if isShiftDown { modifiers.append("⇧") }
        
        // Combine modifiers with key
        if modifiers.isEmpty {
            return keyName.uppercased()
        } else {
            return modifiers.joined(separator: "") + "+" + keyName.uppercased()
        }
    }

    private func setupEventMonitor() {
        let installer = {
            self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if let responder = NSApp.keyWindow?.firstResponder {
                    let className = String(describing: type(of: responder))
                    if className.contains("NSText") || className.contains("TextField") {
                        return event
                    }
                }
                if self.isTextInputActive {
                    return event
                }
                self.handleKeyEvent(event: event)
                return nil
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
    
    private func resolvePattern(for chordName: String) -> GuitarPattern? {
        let group = appData.performanceConfig.patternGroups[currentGroupIndex]
        let timeSig = appData.performanceConfig.timeSignature
        
        var patternId: String? = nil

        // 1. Check for a chord-specific fingering override.
        if let specificId = group.chordAssignments[chordName]?.fingeringId, !specificId.isEmpty {
            patternId = specificId
        } else {
            // 2. Fall back to the group's default fingering (new pattern field).
            patternId = group.pattern
        }
        
        guard let finalPatternId = patternId, !finalPatternId.isEmpty else {
            print("[KeyboardHandler] No pattern ID resolved for chord \(chordName) in group \(group.name)")
            return nil
        }

        // 3. Find the pattern object from the library using the resolved ID.
        if let patternsForTimeSig = appData.patternLibrary?[timeSig] {
            return patternsForTimeSig.first { $0.id == finalPatternId }
        }
        
        return nil
    }

    func handleKeyEvent(event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }

        // --- NEW LOGIC FOR SHORTCUT CAPTURE ---
        if isCapturingShortcut {
            if let chordName = targetChordForShortcutCapture {
                let capturedKey = formatShortcutKey(event: event)
                onShortcutCaptured?(chordName, capturedKey)
                stopCapturingShortcut() // Stop capture after one key
            }
            return // Consume the event, don't process for musical actions
        }
        // --- END NEW LOGIC ---

        let isControlDown = event.modifierFlags.contains(.control)
        let isShiftDown = event.modifierFlags.contains(.shift)
        let isOptionDown = event.modifierFlags.contains(.option)
        let isCommandDown = event.modifierFlags.contains(.command)

        let keyName: String
        switch event.keyCode {
        case 126: keyName = "up"
        case 125: keyName = "down"
        case 24: keyName = "equal"
        case 27: keyName = "minus"
        case 49: keyName = "space"
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

        let quantizeToggleKey = appData.performanceConfig.quantizeToggleKey ?? "q"
        if keyName == quantizeToggleKey {
            let modes = [QuantizationMode.none.rawValue, QuantizationMode.measure.rawValue, QuantizationMode.halfMeasure.rawValue]
            if let currentIndex = modes.firstIndex(of: quantizationMode) {
                quantizationMode = modes[(currentIndex + 1) % modes.count]
            } else {
                quantizationMode = modes.first ?? "MEASURE"
            }
            appData.performanceConfig.quantize = quantizationMode
            return
        }

        if keyName == "p" {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            } else {
                drumPlayer.playPattern(tempo: currentTempo, velocity: 100, durationMs: 200)
            }
            return
        }
        if keyName == "o" {
            drumPlayer.stop()
            return
        }

        if isCommandDown, let number = Int(keyName), number >= 1 && number <= 9 {
            if let drumsForTimeSig = appData.drumPatternLibrary?[currentTimeSignature] {
                let sortedDrumPatternKeys = drumsForTimeSig.keys.sorted()
                let patternIndex = number - 1
                if sortedDrumPatternKeys.indices.contains(patternIndex) {
                    let patternName = sortedDrumPatternKeys[patternIndex]
                    appData.performanceConfig.drumPattern = patternName
                    if drumPlayer.isPlaying {
                        drumPlayer.playPattern(tempo: currentTempo, velocity: 100, durationMs: 200)
                    }
                }
            }
            return
        }

        if keyName == "equal" || keyName == "plus" || characters == "=" {
            currentKeyIndex = (currentKeyIndex + 1) % appData.KEY_CYCLE.count
            appData.performanceConfig.key = appData.KEY_CYCLE[currentKeyIndex]
            return
        }
        if keyName == "minus" || keyName == "underscore" || characters == "-" {
            currentKeyIndex = (currentKeyIndex - 1 + appData.KEY_CYCLE.count) % appData.KEY_CYCLE.count
            appData.performanceConfig.key = appData.KEY_CYCLE[currentKeyIndex]
            return
        }

        if keyName == "up" {
            currentTempo = min(240, currentTempo + 5)
            metronome.tempo = currentTempo
            return
        }
        if keyName == "down" {
            currentTempo = max(60, currentTempo - 5)
            metronome.tempo = currentTempo
            return
        }

        if keyName == "t" {
            if let currentIndex = appData.TIME_SIGNATURE_CYCLE.firstIndex(of: currentTimeSignature) {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE[(currentIndex + 1) % appData.TIME_SIGNATURE_CYCLE.count]
            } else {
                currentTimeSignature = appData.TIME_SIGNATURE_CYCLE.first ?? "4/4"
            }
            let parts = currentTimeSignature.split(separator: "/").map(String.init)
            if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                metronome.timeSignatureNumerator = num
                metronome.timeSignatureDenominator = den
                appData.performanceConfig.timeSignature = currentTimeSignature
            }
            return
        }

        if let groupIndex = Int(keyName), groupIndex >= 1 && groupIndex <= 9 {
            let actualGroupIndex = groupIndex - 1
            if appData.performanceConfig.patternGroups.indices.contains(actualGroupIndex) {
                currentGroupIndex = actualGroupIndex
                return
            }
        }

        var chordName: String? = nil

        // NEW LOGIC: Prioritize shortcut from the currently active group
        let currentGroupIndex = self.currentGroupIndex // Get the active group index
        if appData.performanceConfig.patternGroups.indices.contains(currentGroupIndex) {
            let activeGroup = appData.performanceConfig.patternGroups[currentGroupIndex]
            // Create the full shortcut string for comparison
            let currentShortcut = formatShortcutKey(event: event)
            // Iterate through chordAssignments in the active group to find a match
            if let foundChordName = activeGroup.chordAssignments.first(where: { (key, value) in
                return value.shortcutKey == currentShortcut
            })?.key {
                chordName = foundChordName
            }
        }

        // Existing logic (fallback if not found in active group's shortcuts)
        if chordName == nil { // Only proceed if chordName hasn't been found yet
            if let mappedChord = appData.performanceConfig.keyMap[keyName] {
                chordName = mappedChord
            } else {
                let simulatedKey = JSKey(name: characters, meta: isCommandDown, alt: isOptionDown, ctrl: isControlDown, shift: isShiftDown)
                chordName = MusicTheory.getChordFromDefaultMapping(key: simulatedKey)
            }
        }

        if let chord = chordName {
            markChordActive(chord)
            
            if let finalPattern = resolvePattern(for: chord) {
                let durationSeconds = TimeInterval(appData.CONFIG.duration) / 1000.0
                let keyString = appData.KEY_CYCLE[currentKeyIndex]
                let quantMode = quantizationMode

                if quantMode == QuantizationMode.none.rawValue {
                    guitarPlayer.playChord(chordName: chord, pattern: finalPattern, tempo: currentTempo, key: keyString, velocity: UInt8(appData.CONFIG.velocity), duration: durationSeconds)
                } else {
                    let clock = drumPlayer.clockInfo
                    if !clock.isPlaying || clock.loopDuration <= 0 {
                        guitarPlayer.playChord(chordName: chord, pattern: finalPattern, tempo: currentTempo, key: keyString, velocity: UInt8(appData.CONFIG.velocity), duration: durationSeconds)
                    } else {
                        var division = 1.0
                        if quantMode == QuantizationMode.halfMeasure.rawValue {
                            division = 2.0
                        }
                        let quantizationInterval = clock.loopDuration / division
                        let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
                        let loopElapsedTime = fmod(nowUptimeMs - clock.startTime, clock.loopDuration)
                        let currentInterval = floor(loopElapsedTime / quantizationInterval)
                        let timeToNextIntervalStart = ((currentInterval + 1.0) * quantizationInterval) - loopElapsedTime
                        let QUANTIZATION_WINDOW_PERCENT = 0.5
                        let quantizationWindow = quantizationInterval * QUANTIZATION_WINDOW_PERCENT

                        if timeToNextIntervalStart <= quantizationWindow {
                            let delaySeconds = timeToNextIntervalStart / 1000.0
                            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                                guard let self = self else { return }
                                self.guitarPlayer.playChord(chordName: chord, pattern: finalPattern, tempo: self.currentTempo, key: keyString, velocity: UInt8(self.appData.CONFIG.velocity), duration: durationSeconds)
                            }
                        } else {
                            return
                        }
                    }
                }
            } else {
                print("\nError: Could not resolve pattern data for \(chord).")
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func playChordButton(chordName: String) {
        markChordActive(chordName)
        if let finalPattern = resolvePattern(for: chordName) {
            let durationSeconds = TimeInterval(appData.CONFIG.duration) / 1000.0
            let keyString = appData.KEY_CYCLE[currentKeyIndex]
            guitarPlayer.playChord(chordName: chordName, pattern: finalPattern, tempo: currentTempo, key: keyString, velocity: UInt8(appData.CONFIG.velocity), duration: durationSeconds)
        } else {
            print("[KeyboardHandler] playChordButton: could not resolve pattern for \(chordName)")
        }
    }
    
    private func markChordActive(_ chord: String) {
        DispatchQueue.main.async {
            self.activeChordName = chord
            self.activeChordClearWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.activeChordName = nil
                }
            }
            self.activeChordClearWorkItem = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }
}

