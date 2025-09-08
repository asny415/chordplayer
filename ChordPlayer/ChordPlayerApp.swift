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

    @State private var showCustomChordCreatorFromMenu = false
    @State private var showCustomChordManagerFromMenu = false
    @State private var showDrumPatternCreatorFromMenu = false
    @State private var showCustomDrumPatternManagerFromMenu = false
    @State private var showPlayingPatternCreatorFromMenu = false
    @State private var showCustomPlayingPatternManagerFromMenu = false


    var body: some Scene {
        WindowGroup {
            ContentView(
                showCustomChordCreatorFromMenu: $showCustomChordCreatorFromMenu,
                showCustomChordManagerFromMenu: $showCustomChordManagerFromMenu,
                showDrumPatternCreatorFromMenu: $showDrumPatternCreatorFromMenu,
                showCustomDrumPatternManagerFromMenu: $showCustomDrumPatternManagerFromMenu,
                showPlayingPatternCreatorFromMenu: $showPlayingPatternCreatorFromMenu,
                showCustomPlayingPatternManagerFromMenu: $showCustomPlayingPatternManagerFromMenu
            )
                .environmentObject(appData)
                .environmentObject(midiManager)
                .environmentObject(metronome)
                .environmentObject(chordPlayer)
                .environmentObject(drumPlayer)
                .environmentObject(keyboardHandler)
                .environmentObject(PresetManager.shared)
                .environmentObject(CustomChordManager.shared)
                .environmentObject(CustomDrumPatternManager.shared)
                .environmentObject(CustomPlayingPatternManager.shared)
        }
        .commands {
            CommandMenu("自定义库") {
                Button("创建自定义和弦...") {
                    showCustomChordCreatorFromMenu = true
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])
                
                Button("创建自定义鼓点...") {
                    showDrumPatternCreatorFromMenu = true
                }
                
                Button("创建自定义演奏模式...") {
                    showPlayingPatternCreatorFromMenu = true
                }
                
                Divider()

                Button("管理自定义和弦...") {
                    showCustomChordManagerFromMenu = true
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])
                
                Button("管理自定义鼓点...") {
                    showCustomDrumPatternManagerFromMenu = true
                }
                
                Button("管理自定义演奏模式...") {
                    showCustomPlayingPatternManagerFromMenu = true
                }
            }
        }
    }
}
