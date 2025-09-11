import Foundation
import SwiftUI
import AppKit
import Combine

struct PlayingInfo {
    let chordName: String
    let shortcut: String
    var duration: Int?
}

class KeyboardHandler: ObservableObject {
    private var midiManager: MidiManager
    private var chordPlayer: ChordPlayer
    private var drumPlayer: DrumPlayer
    private var appData: AppData
    private let customPlayingPatternManager: CustomPlayingPatternManager

    @Published var lastPlayedChord: String? = nil
    @Published var currentPlayingInfo: PlayingInfo? = nil
    @Published var nextPlayingInfo: PlayingInfo? = nil
    @Published var beatsToNextChord: Int? = nil
    @Published var currentChordProgress: Double = 0.0

    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager, chordPlayer: ChordPlayer, drumPlayer: DrumPlayer, appData: AppData, customPlayingPatternManager: CustomPlayingPatternManager) {
        self.midiManager = midiManager
        self.chordPlayer = chordPlayer
        self.drumPlayer = drumPlayer
        self.appData = appData
        self.customPlayingPatternManager = customPlayingPatternManager

        setupEventMonitor()

        appData.$performanceConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.updateWithNewConfig(newConfig)
            }
            .store(in: &cancellables)

        appData.$currentBeat
            .combineLatest(appData.$currentMeasure)
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] beat, measure in
                guard let self = self else { return }

                if !([.automatic, .assisted].contains(self.appData.playingMode)) || self.appData.autoPlaySchedule.isEmpty {
                    self.currentPlayingInfo = nil
                    self.nextPlayingInfo = nil
                    self.beatsToNextChord = nil
                    self.currentChordProgress = 0.0 // Reset progress
                    return
                }

                var beatsPerMeasure = 4
                let timeSigParts = self.appData.performanceConfig.timeSignature.split(separator: "/")
                if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
                    beatsPerMeasure = beats
                }

                let currentTotalBeats: Int
                if measure == 0 { // Count-in phase
                    currentTotalBeats = beat
                } else { // Normal playback
                    currentTotalBeats = (measure - 1) * beatsPerMeasure + beat
                }

                self.updatePlayingInfo(currentTotalBeats: currentTotalBeats)

                // 每次拍子变化时重置active位置的触发状态
                self.appData.currentActivePositionTriggered = false

                let triggerBeat = currentTotalBeats + 1
                for event in self.appData.autoPlaySchedule {
                    if event.triggerBeat == triggerBeat {
                        // In assisted mode, we follow the schedule but don't play the chord.
                        if self.appData.playingMode != .assisted {
                            self.playChord(chordName: event.chordName, withPatternId: event.patternId, fromAutoPlay: true)
                        }
                    }
                }
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
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }


            // If the current first responder appears to be a text input control
            // that belongs to the key window's view hierarchy, let the event
            // pass through so the control can receive typing.
            if let responder = NSApp.keyWindow?.firstResponder,
               let view = responder as? NSView {

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
        if event.keyCode == 126 { // Up arrow
            appData.performanceConfig.tempo = min(240, appData.performanceConfig.tempo + 5)
            return true
        } else if event.keyCode == 125 { // Down arrow
            appData.performanceConfig.tempo = max(40, appData.performanceConfig.tempo - 5)
            return true
        }

        if characters == "q" && !flags.contains(.command) {
            let current = QuantizationMode(rawValue: appData.performanceConfig.quantize ?? "NONE") ?? .none
            let all = QuantizationMode.allCases
            if let idx = all.firstIndex(of: current) {
                let next = all[(idx + 1) % all.count]
                appData.performanceConfig.quantize = next.rawValue
            } else if let first = all.first {
                appData.performanceConfig.quantize = first.rawValue
            }
            return true
        }

        if characters == "t" && !flags.contains(.command) {
            let options = appData.TIME_SIGNATURE_CYCLE
            if let idx = options.firstIndex(of: appData.performanceConfig.timeSignature) {
                let next = options[(idx + 1) % options.count]
                appData.performanceConfig.timeSignature = next
            } else if let first = options.first {
                appData.performanceConfig.timeSignature = first
            }
            return true
        }

        if (characters == "-" || characters == "=") && !flags.contains(.command) {
            let cycle = appData.KEY_CYCLE
            guard !cycle.isEmpty else { return true }
            if let idx = cycle.firstIndex(of: appData.performanceConfig.key) {
                let nextIdx: Int
                if characters == "=" { nextIdx = (idx + 1) % cycle.count }
                else { nextIdx = (idx - 1 + cycle.count) % cycle.count }
                appData.performanceConfig.key = cycle[nextIdx]
            } else {
                appData.performanceConfig.key = (characters == "=") ? cycle.first! : cycle.last!
            }
            return true
        }

        if flags.contains(.command) {
            return handleCommandShortcuts(characters: characters)
        }

        if let number = Int(characters), number >= 1 && number <= 9 {
            return handleNumericShortcuts(number: number)
        }

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

        if characters == "m" {
            appData.playingMode = appData.playingMode.next()
            return true
        }

        if let shortcut = Shortcut.from(event: event) {
            // Priority 1: Check for specific pattern associations
            for chordConfig in appData.performanceConfig.chords {
                if let association = chordConfig.patternAssociations[shortcut] {
                    playChord(chordName: chordConfig.name, withPatternId: association.patternId)
                    // 在辅助演奏模式下，检查是否触发了当前active位置的正确按键
                    checkAndTriggerActivePosition(for: chordConfig.name)
                    return true // Event is handled whether played or not
                }
            }
            
            // Priority 2: Check for general chord shortcuts
            if let chordName = resolveChordForShortcut(shortcut) {
                playChord(chordName: chordName)
                // 在辅助演奏模式下，检查是否触发了当前active位置的正确按键
                checkAndTriggerActivePosition(for: chordName)
                return true
            }
        }

        return false
    }

    private func resolveChordForShortcut(_ shortcut: Shortcut) -> String? {
        // 1. Check current preset custom mappings
        for chordConfig in appData.performanceConfig.chords {
            if chordConfig.shortcut == shortcut.stringValue {
                return chordConfig.name
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

    private func playChord(chordName: String, withPatternId patternIdOverride: String? = nil, fromAutoPlay: Bool = false) {
        let patternIdToPlay = patternIdOverride ?? appData.performanceConfig.activePlayingPatternId
        
        guard let playingPatternId = patternIdToPlay else {
            print("Error: No active or override playing pattern specified.")
            return
        }
        
        let timeSignature = appData.performanceConfig.timeSignature
        
        var pattern: GuitarPattern?
        if let library = appData.patternLibrary?[timeSignature] {
            pattern = library.first(where: { $0.id == playingPatternId })
        }
        if pattern == nil, let customLibrary = customPlayingPatternManager.customPlayingPatterns[timeSignature] {
            pattern = customLibrary.first(where: { $0.id == playingPatternId })
        }
        
        guard let foundPattern = pattern else {
            print("Error: Could not resolve playing pattern with ID \(playingPatternId).")
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
            if !fromAutoPlay {
                self.currentPlayingInfo = PlayingInfo(chordName: chordName, shortcut: self.shortcutForChord(chordName) ?? "")
                self.nextPlayingInfo = nil
                self.beatsToNextChord = nil
                self.currentChordProgress = 0.0
            }
            self.lastPlayedChord = chordName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.lastPlayedChord = nil
            }
        }
    }

    private func updatePlayingInfo(currentTotalBeats: Int) {
        let schedule = appData.autoPlaySchedule
        guard !schedule.isEmpty else {
            currentPlayingInfo = nil
            nextPlayingInfo = nil
            beatsToNextChord = nil
            currentChordProgress = 0.0
            return
        }

        // --- Special case for count-in ---
        if currentTotalBeats < 0 {
            currentPlayingInfo = nil // Nothing is "currently" playing

            let firstEvent = schedule.first!
            let shortcutText = Shortcut(stringValue: firstEvent.shortcut ?? "")?.displayText ?? ""
            
            // The "next" thing to happen is the first chord
            nextPlayingInfo = PlayingInfo(chordName: firstEvent.chordName, shortcut: shortcutText, duration: firstEvent.durationBeats)

            // The countdown is to beat 0
            beatsToNextChord = -currentTotalBeats - 1
            
            // Progress of the count-in
            var beatsPerMeasure = 4
            let timeSigParts = self.appData.performanceConfig.timeSignature.split(separator: "/")
            if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
                beatsPerMeasure = beats
            }
            let totalCountInBeats = beatsPerMeasure
            let elapsedCountInBeats = totalCountInBeats + currentTotalBeats
            currentChordProgress = Double(elapsedCountInBeats) / Double(totalCountInBeats)
            
            return // End of count-in handling
        }

        // --- Normal Playback ---
        var currentEvent: AutoPlayEvent?
        var nextEvent: AutoPlayEvent?

        if let currentEventIndex = schedule.lastIndex(where: { $0.triggerBeat <= currentTotalBeats }) {
            currentEvent = schedule[currentEventIndex]
            if currentEventIndex + 1 < schedule.count {
                nextEvent = schedule[currentEventIndex + 1]
            }
        }

        if let event = currentEvent {
            let shortcutText = Shortcut(stringValue: event.shortcut ?? "")?.displayText ?? ""
            if currentPlayingInfo?.chordName != event.chordName || currentPlayingInfo?.shortcut != shortcutText {
                 currentPlayingInfo = PlayingInfo(chordName: event.chordName, shortcut: shortcutText, duration: event.durationBeats)
            }
        } else {
            currentPlayingInfo = nil
        }

        if let event = nextEvent {
            let shortcutText = Shortcut(stringValue: event.shortcut ?? "")?.displayText ?? ""
            if nextPlayingInfo?.chordName != event.chordName || nextPlayingInfo?.shortcut != shortcutText {
                nextPlayingInfo = PlayingInfo(chordName: event.chordName, shortcut: shortcutText, duration: event.durationBeats)
            }
            
            // Calculate progress towards the next event
            let trigger = event.triggerBeat
            let prevTrigger = currentEvent?.triggerBeat ?? 0
            let totalDuration = trigger - prevTrigger
            
            if totalDuration > 0 {
                let progress = currentTotalBeats - prevTrigger
                currentChordProgress = Double(progress) / Double(totalDuration)
                beatsToNextChord = totalDuration - progress - 1
            } else {
                currentChordProgress = 0
                beatsToNextChord = 0
            }
            
        } else {
            nextPlayingInfo = nil
            // Handle progress for the very last chord
            if let lastEvent = currentEvent, let duration = lastEvent.durationBeats, duration > 0 {
                let progress = currentTotalBeats - lastEvent.triggerBeat
                currentChordProgress = Double(progress) / Double(duration)
                beatsToNextChord = duration - progress - 1
            } else {
                currentChordProgress = 1.0
                beatsToNextChord = 0
            }
        }
    }

    // 检查用户是否在辅助演奏模式下按下了当前active位置的正确按键
    private func checkAndTriggerActivePosition(for chordName: String) {
        guard appData.playingMode == .assisted else { return }
        
        // 计算当前总拍数，与AssistPlayingView中的逻辑一致
        let beatsPerMeasure: Int = {
            let timeSigParts = appData.performanceConfig.timeSignature.split(separator: "/")
            return Int(timeSigParts.first.map(String.init) ?? "4") ?? 4
        }()
        
        let currentTotalBeat: Int
        if appData.currentMeasure == 0 {
            currentTotalBeat = appData.effectiveCurrentBeat
        } else {
            currentTotalBeat = (appData.currentMeasure - 1) * beatsPerMeasure + appData.effectiveCurrentBeat
        }
        
        // 计算active位置的拍子（index=2，即提前一拍）
        let activeBeat = currentTotalBeat - 1 + 2
        
        // 检查autoPlaySchedule中在这个拍子是否有事件，且事件的和弦名称匹配
        if let event = appData.autoPlaySchedule.first(where: { $0.triggerBeat == activeBeat }),
           event.chordName == chordName {
            // 用户按下了正确的按键！
            appData.currentActivePositionTriggered = true
        }
    }

    private func shortcutForChord(_ chordName: String) -> String? {
        if let chordConfig = appData.performanceConfig.chords.first(where: { $0.name == chordName }) {
            if let shortcutValue = chordConfig.shortcut, let s = Shortcut(stringValue: shortcutValue) {
                return s.displayText
            }
        }
        
        let components = chordName.split(separator: "_")
        if components.count >= 2 {
            let quality = String(components.last!)
            let noteParts = components.dropLast()
            let noteRaw = noteParts.joined(separator: "_")
            let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")

            if noteDisplay.count == 1 {
                if quality == "Major" {
                    return noteDisplay.uppercased()
                } else if quality == "Minor" {
                    return "⇧\(noteDisplay.uppercased())"
                }
            }
        }
        return nil
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


