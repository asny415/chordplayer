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
    // 添加鼓点/指法的面板已移到对应的工作区视图中，因此不再需要全局 sheet 状态

    var body: some Scene {
        WindowGroup {
            ContentView(
                showCustomChordCreatorFromMenu: $showCustomChordCreatorFromMenu,
                showCustomChordManagerFromMenu: $showCustomChordManagerFromMenu
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
            CommandGroup(after: .appSettings) {
                Button("创建自定义和弦...") {
                    showCustomChordCreatorFromMenu = true
                }
                .keyboardShortcut("N", modifiers: [.command, .shift])

                Button("管理自定义和弦...") {
                    showCustomChordManagerFromMenu = true
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])

                // 移除菜单中的“添加鼓点模式”和“添加和弦指法”项，
                // 使用面板内的添加按钮替代以改善可发现性和上下文相关性。
            }
        }
    }
}
