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
    @StateObject private var chordPlayer: ChordPlayer
    @StateObject private var drumPlayer: DrumPlayer
    @StateObject private var keyboardHandler: KeyboardHandler // Add this

    init() {
        let customChordManager = CustomChordManager.shared
        let customDrumPatternManager = CustomDrumPatternManager.shared
        let customPlayingPatternManager = CustomPlayingPatternManager.shared
        let initialAppData = AppData(customChordManager: customChordManager)
        let initialMidiManager = MidiManager()
        let initialChordPlayer = ChordPlayer(midiManager: initialMidiManager, appData: initialAppData)
        let initialDrumPlayer = DrumPlayer(midiManager: initialMidiManager, appData: initialAppData, customDrumPatternManager: customDrumPatternManager)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData, customPlayingPatternManager: customPlayingPatternManager)

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _chordPlayer = StateObject(wrappedValue: initialChordPlayer)
        _drumPlayer = StateObject(wrappedValue: initialDrumPlayer)
        _keyboardHandler = StateObject(wrappedValue: initialKeyboardHandler)
    }

    @State private var showCustomChordCreatorFromMenu = false
    @State private var showCustomChordManagerFromMenu = false
    @State private var showDrumPatternCreatorFromMenu = false
    @State private var showCustomDrumPatternManagerFromMenu = false
    @State private var showPlayingPatternCreatorFromMenu = false
    @State private var showCustomPlayingPatternManagerFromMenu = false
    @State private var showLyricsManagerFromMenu = false


    @Environment(\.openWindow) var openWindow

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
                .environmentObject(chordPlayer)
                .environmentObject(drumPlayer)
                .environmentObject(keyboardHandler)
                .environmentObject(PresetManager.shared)
                .environmentObject(CustomChordManager.shared)
                .environmentObject(CustomDrumPatternManager.shared)
                .environmentObject(CustomPlayingPatternManager.shared)
        }
        .onChange(of: appData.showTimingWindow) { oldValue, newValue in
            if newValue {
                openWindow(id: "timing-display")
            }
        }
        
        Window("演奏助手", id: "timing-display") {
            TimingDisplayWindowView()
                .environmentObject(appData)
                .environmentObject(keyboardHandler)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        
        Window("曲谱编辑器", id: "sheet-music-editor") {
            SheetMusicEditorWindow()
                .environmentObject(appData)
                .environmentObject(keyboardHandler)
                .environmentObject(PresetManager.shared)
                .environmentObject(CustomChordManager.shared)
                .environmentObject(CustomDrumPatternManager.shared)
                .environmentObject(CustomPlayingPatternManager.shared)
        }
        .keyboardShortcut("E", modifiers: .command)
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
