import SwiftUI
import UniformTypeIdentifiers

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
    @StateObject private var melodicLyricPlayer: MelodicLyricPlayer

    init() {
        let initialMidiManager = MidiManager()
        let initialAppData = AppData(midiManager: initialMidiManager)
        let initialMidiSequencer = MIDISequencer(midiManager: initialMidiManager)
        // TODO: Refactor these initializers to remove dependencies on old managers
        let initialDrumPlayer = DrumPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData)
        let initialChordPlayer = ChordPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData)
        let initialSoloPlayer = SoloPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData)
        let initialMelodicLyricPlayer = MelodicLyricPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData)
        let initialPresetArrangerPlayer = PresetArrangerPlayer(midiSequencer: initialMidiSequencer, midiManager: initialMidiManager, appData: initialAppData, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, soloPlayer: initialSoloPlayer, melodicLyricPlayer: initialMelodicLyricPlayer)
        let initialKeyboardHandler = KeyboardHandler(midiManager: initialMidiManager, chordPlayer: initialChordPlayer, drumPlayer: initialDrumPlayer, appData: initialAppData)

        _appData = StateObject(wrappedValue: initialAppData)
        _midiManager = StateObject(wrappedValue: initialMidiManager)
        _midiSequencer = StateObject(wrappedValue: initialMidiSequencer)
        _chordPlayer = StateObject(wrappedValue: initialChordPlayer)
        _drumPlayer = StateObject(wrappedValue: initialDrumPlayer)
        _soloPlayer = StateObject(wrappedValue: initialSoloPlayer)
        _presetArrangerPlayer = StateObject(wrappedValue: initialPresetArrangerPlayer)
        _keyboardHandler = StateObject(wrappedValue: initialKeyboardHandler)
        _melodicLyricPlayer = StateObject(wrappedValue: initialMelodicLyricPlayer)

        
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
                .environmentObject(melodicLyricPlayer)
                .environmentObject(PresetManager.shared)
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Save As...") {
                    showSavePanel()
                }
                .keyboardShortcut("S", modifiers: [.shift, .command])
            }
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
    
    private func showSavePanel() {
        let presetManager = PresetManager.shared
        guard let preset = presetManager.currentPreset else { return }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "\(preset.name).json"
        
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                presetManager.savePresetAs(to: url)
            }
        }
    }
}