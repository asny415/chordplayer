//
//  ChordPlayerApp.swift
//  ChordPlayer
//
//  Created by wwq on 2025/8/31.
//

import SwiftUI

@main
struct ChordPlayerApp: App {
    @StateObject private var appData: AppData
    @StateObject private var midiManager: MidiManager
    @StateObject private var metronome: Metronome
    @StateObject private var chordPlayer: ChordPlayer
    @StateObject private var drumPlayer: DrumPlayer
    @StateObject private var keyboardHandler: KeyboardHandler // Add this

    init() {
        let initialAppData = AppData()
        let initialMidiManager = MidiManager()
        let initialMetronome = Metronome(midiManager: initialMidiManager)
        let initialChordPlayer = ChordPlayer(midiManager: initialMidiManager, metronome: initialMetronome, appData: initialAppData)
        let initialDrumPlayer = DrumPlayer(midiManager: initialMidiManager, metronome: initialMetronome, appData: initialAppData)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, metronome: initialMetronome, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData) // Initialize KeyboardHandler

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _metronome = StateObject(wrappedValue: initialMetronome)
        _chordPlayer = StateObject(wrappedValue: initialChordPlayer)
        _drumPlayer = StateObject(wrappedValue: initialDrumPlayer)
        _keyboardHandler = StateObject(wrappedValue: initialKeyboardHandler) // Assign KeyboardHandler
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
                .environmentObject(midiManager)
                .environmentObject(metronome)
                .environmentObject(chordPlayer)
                .environmentObject(drumPlayer)
                .environmentObject(keyboardHandler) // Add this
                .environmentObject(PresetManager.shared)
        }
    }
}
