import SwiftUI

@main
struct ChordPlayerApp: App {
    @StateObject private var appData: AppData
    @StateObject private var midiManager: MidiManager
    @StateObject private var chordPlayer: ChordPlayer
    @StateObject private var drumPlayer: DrumPlayer
    @StateObject private var midiSequencer: MIDISequencer
    @StateObject private var soloPlayer: SoloPlayer
    @StateObject private var presetArrangerPlayer: PresetArrangerPlayer
    @StateObject private var keyboardHandler: KeyboardHandler

    init() {
        let initialMidiManager = MidiManager()
        let initialAppData = AppData(midiManager: initialMidiManager)
        let initialMidiSequencer = MIDISequencer(midiManager: initialMidiManager)
        // TODO: Refactor these initializers to remove dependencies on old managers
        let initialDrumPlayer = DrumPlayer(midiManager: initialMidiManager, appData: initialAppData)
        let initialChordPlayer = ChordPlayer(midiManager: initialMidiManager, appData: initialAppData, drumPlayer: initialDrumPlayer)
        let initialSoloPlayer = SoloPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData)
        let initialPresetArrangerPlayer = PresetArrangerPlayer(midiManager: initialMidiManager, appData: initialAppData, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, soloPlayer: initialSoloPlayer)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData)

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _midiSequencer = StateObject(wrappedValue: initialMidiSequencer)
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
                .environmentObject(midiSequencer)
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
        .keyboardShortcut("r", modifiers: .command)
    }
}