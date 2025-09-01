//
//  guitarPlayerApp.swift
//  guitarPlayer
//
//  Created by wwq on 2025/8/31.
//

import SwiftUI

@main
struct guitarPlayerApp: App {
    @StateObject private var appData: AppData
    @StateObject private var midiManager: MidiManager
    @StateObject private var metronome: Metronome
    @StateObject private var guitarPlayer: GuitarPlayer
    @StateObject private var drumPlayer: DrumPlayer
    @StateObject private var keyboardHandler: KeyboardHandler // Add this

    init() {
        let initialAppData = AppData()
        let initialMidiManager = MidiManager()
        let initialMetronome = Metronome(midiManager: initialMidiManager)
        let initialGuitarPlayer = GuitarPlayer(midiManager: initialMidiManager, metronome: initialMetronome, appData: initialAppData)
        let initialDrumPlayer = DrumPlayer(midiManager: initialMidiManager, metronome: initialMetronome, appData: initialAppData)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, metronome: initialMetronome, guitarPlayer: initialGuitarPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData) // Initialize KeyboardHandler

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _metronome = StateObject(wrappedValue: initialMetronome)
        _guitarPlayer = StateObject(wrappedValue: initialGuitarPlayer)
        _drumPlayer = StateObject(wrappedValue: initialDrumPlayer)
        _keyboardHandler = StateObject(wrappedValue: initialKeyboardHandler) // Assign KeyboardHandler
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
                .environmentObject(midiManager)
                .environmentObject(metronome)
                .environmentObject(guitarPlayer)
                .environmentObject(drumPlayer)
                .environmentObject(keyboardHandler) // Add this
        }
    }
}
