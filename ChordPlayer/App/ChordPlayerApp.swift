import SwiftUI

@main
struct ChordPlayerApp: App {
    @StateObject private var appData: AppData
    @StateObject private var midiManager: MidiManager
    @StateObject private var chordPlayer: ChordPlayer
    @StateObject private var drumPlayer: DrumPlayer
    @StateObject private var soloPlayer: SoloPlayer
    @StateObject private var presetArrangerPlayer: PresetArrangerPlayer
    @StateObject private var keyboardHandler: KeyboardHandler

    init() {
        let initialMidiManager = MidiManager()
        let initialAppData = AppData(midiManager: initialMidiManager)
        // TODO: Refactor these initializers to remove dependencies on old managers
        let initialDrumPlayer = DrumPlayer(midiManager: initialMidiManager, appData: initialAppData)
        let initialChordPlayer = ChordPlayer(midiManager: initialMidiManager, appData: initialAppData, drumPlayer: initialDrumPlayer)
        let initialSoloPlayer = SoloPlayer(midiManager: initialMidiManager, appData: initialAppData, drumPlayer: initialDrumPlayer)
        let initialPresetArrangerPlayer = PresetArrangerPlayer(midiManager: initialMidiManager, appData: initialAppData, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, soloPlayer: initialSoloPlayer)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData)

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _chordPlayer = StateObject(wrappedValue: initialChordPlayer)
        _drumPlayer = StateObject(wrappedValue: initialDrumPlayer)
        _soloPlayer = StateObject(wrappedValue: initialSoloPlayer)
        _presetArrangerPlayer = StateObject(wrappedValue: initialPresetArrangerPlayer)
        _keyboardHandler = StateObject(wrappedValue: initialKeyboardHandler)

        
    }

    @Environment(\.openWindow) var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
                .environmentObject(midiManager)
                .environmentObject(chordPlayer)
                .environmentObject(drumPlayer)
                .environmentObject(soloPlayer)
                .environmentObject(presetArrangerPlayer)
                .environmentObject(keyboardHandler)
                .environmentObject(PresetManager.shared)
        }
        
        Settings {
            PreferencesView()
                .environmentObject(appData)
                .environmentObject(midiManager)
        }
        
        Window("演奏助手", id: "timing-display") {
            // TODO: This view needs to be updated or might be obsolete
            // TimingDisplayWindowView()
            //     .environmentObject(appData)
            //     .environmentObject(keyboardHandler)
            Text("Timing Display Window - Needs Update")
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 250)
        .windowResizability(.contentMinSize)
        
        Window("曲谱编辑器", id: "sheet-music-editor") {
            // TODO: This view needs to be updated or might be obsolete
            // SheetMusicEditorWindow()
            //     .environmentObject(appData)
            //     .environmentObject(keyboardHandler)
            //     .environmentObject(PresetManager.shared)
            Text("Sheet Music Editor - Needs Update")
        }
        .keyboardShortcut("E", modifiers: .command)
        // TODO: Re-implement a new, relevant command menu if needed.
        // .commands { ... }
        
        Window("Song Arranger", id: "song-arranger") {
            NavigationStack {
                // We need to ensure a preset is loaded. A simple check and message is best.
                if let preset = appData.preset {
                    SimplePresetArrangerView()
                        .navigationTitle("Arrange: \(preset.name)")
                        .environmentObject(appData)
                        .environmentObject(presetArrangerPlayer)
                } else {
                    VStack {
                        Text("No Preset Loaded")
                            .font(.title)
                        Text("Please load a preset from the main window before opening the arranger.")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .defaultSize(width: 1200, height: 700)
        .windowResizability(.contentSize)
    }
}