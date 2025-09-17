import Foundation
import SwiftUI
import AppKit
import Combine

class KeyboardHandler: ObservableObject {
    private var midiManager: MidiManager
    private var chordPlayer: ChordPlayer
    private var drumPlayer: DrumPlayer
    private var appData: AppData

    @Published var lastPlayedChord: String? = nil

    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager, chordPlayer: ChordPlayer, drumPlayer: DrumPlayer, appData: AppData) {
        self.midiManager = midiManager
        self.chordPlayer = chordPlayer
        self.drumPlayer = drumPlayer
        self.appData = appData

        setupEventMonitor()

        // We can observe appData.preset directly if needed, but for now, actions will read from it directly.
    }

    func pauseEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            self.eventMonitor = nil
        }
    }

    func resumeEventMonitoring() {
        if eventMonitor == nil {
            setupEventMonitor()
        }
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView || responder is NSTextField {
                return event
            }

            let handled = self.handleKeyEvent(event: event)
            return handled ? nil : event
        }
    }

    private func handleKeyEvent(event: NSEvent) -> Bool {
        guard let preset = appData.preset else { return false }
        
        // Simplified shortcuts
        if event.keyCode == 49 { // Space bar
            if let firstChordName = preset.chordProgression.first {
                playChord(chordName: firstChordName)
                return true
            }
        }
        
        // TODO: Re-implement more complex shortcut handling
        // For now, we are keeping it simple to ensure compilation.

        return false
    }

    private func playChord(chordName: String, withPatternId patternIdOverride: UUID? = nil) {
        guard let preset = appData.preset else { return }
        
        guard let chordToPlay = preset.chords.first(where: { $0.name == chordName }) else {
            print("Error: Could not find chord with name \(chordName)")
            return
        }

        let patternIdToPlay = patternIdOverride ?? preset.activePlayingPatternId
        
        guard let playingPatternId = patternIdToPlay,
              let patternToPlay = preset.playingPatterns.first(where: { $0.id == playingPatternId }) else {
            print("Error: Could not find active playing pattern with ID \(String(describing: patternIdToPlay))")
            return
        }
        
        // Calculate a sensible duration for the pattern based on its properties
        let wholeNoteSeconds = (60.0 / Double(preset.bpm)) * 4.0
        let stepsPerWholeNote = patternToPlay.resolution == .sixteenth ? 16.0 : 8.0
        let singleStepDuration = wholeNoteSeconds / stepsPerWholeNote
        let totalDuration = singleStepDuration * Double(patternToPlay.length)

        chordPlayer.schedulePattern(
            chord: chordToPlay,
            pattern: patternToPlay,
            preset: preset,
            scheduledUptime: ProcessInfo.processInfo.systemUptime, // Play immediately
            totalDuration: totalDuration,
            dynamics: .medium // Use a default dynamic for keyboard triggers
        )
        
        print("Playing chord \(chordName) with pattern \(patternToPlay.name)")

        DispatchQueue.main.async {
            self.lastPlayedChord = chordName
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.lastPlayedChord = nil
            }
        }
    }

    func playChordByName(_ chordName: String) {
        playChord(chordName: chordName)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}