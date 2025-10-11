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
    @StateObject private var patternEditorSettings = PatternEditorSettings()

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
    @State private var isImporting = false
    @State private var showingImportConflictAlert = false
    @State private var conflictingPreset: Preset?
    @State private var presetsToImport: [Preset] = []
    @State private var showingImportErrorAlert = false
    @State private var importErrorMessage = ""

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
                .environmentObject(patternEditorSettings)
                .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        // This will be a security-scoped URL, so we need to handle it properly.
                        let secured = url.startAccessingSecurityScopedResource()
                        defer {
                            if secured {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }
                        handleImport(from: url)
                    case .failure(let error):
                        print("Error importing file: \(error.localizedDescription)")
                    }
                }
                .alert(Text(LocalizedStringKey("Preset Conflict")), isPresented: $showingImportConflictAlert, presenting: conflictingPreset) { preset in
                    Button(LocalizedStringKey("Overwrite"), role: .destructive) {
                        PresetManager.shared.addOrUpdatePreset(preset)
                        processNextImport()
                    }
                    Button(LocalizedStringKey("Skip"), role: .cancel) {
                        processNextImport()
                    }
                } message: { preset in
                    Text(String(format: NSLocalizedString("A preset named '%@' with the same ID already exists. Do you want to overwrite it?", comment: ""), preset.name))
                }
                .alert(Text(LocalizedStringKey("Import Failed")), isPresented: $showingImportErrorAlert) {
                    Button(LocalizedStringKey("OK"), role: .cancel) { }
                } message: { 
                    Text(importErrorMessage)
                }
        }
        .commands {
            CommandGroup(after: .saveItem) {
                Button("Export...") {
                    showSavePanel()
                }
                .keyboardShortcut("S", modifiers: [.shift, .command])
                
                Button("Import...") {
                    isImporting = true
                }
                .keyboardShortcut("I", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .sidebar) {
                Toggle(isOn: $appData.showDrumPatternSectionByDefault) {
                    Text("menu.view.show_drum_patterns_section")
                }
                .keyboardShortcut("1", modifiers: .option)
                
                Toggle(isOn: $appData.showSoloSegmentSectionByDefault) {
                    Text("menu.view.show_solo_segments_section")
                }
                .keyboardShortcut("2", modifiers: .option)
            }
        }

        
        Settings {
            PreferencesView()
                .environmentObject(appData)
                .environmentObject(midiManager)
        }
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
    
    private func handleImport(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            print("Failed to read data from URL.")
            return
        }

        // First, try to decode as a single Preset
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let preset = try decoder.decode(Preset.self, from: data)
            self.presetsToImport = [preset]
            processNextImport()
        } catch let firstError {
            // If decoding a single preset fails, THEN try decoding an array
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let presets = try decoder.decode([Preset].self, from: data)
                self.presetsToImport = presets
                processNextImport()
            } catch {
                // If both attempts fail, the first error is the most likely root cause.
                // Report the error from the initial attempt to decode a single Preset.
                reportImportError(firstError)
            }
        }
    }

    private func reportImportError(_ error: Error) {
        var detailedErrorMessage = "The file format is not correct. Please use a valid preset file created with the 'Export...' function."

        if let decodingError = error as? DecodingError {
            detailedErrorMessage += "\n\n[Debug Info]\n"
            switch decodingError {
            case .keyNotFound(let key, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: " -> ")
                detailedErrorMessage += "A required field is missing: '\(key.stringValue)'."
                if !path.isEmpty { detailedErrorMessage += "\nPath: \(path)" }
                
            case .typeMismatch(_, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: " -> ")
                detailedErrorMessage += "A field has the wrong data type at path: '\(path)'."
                detailedErrorMessage += "\nDetails: \(context.debugDescription)"

            case .valueNotFound(let type, let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: " -> ")
                detailedErrorMessage += "A required value was null or missing. Expected '\(type)'."
                if !path.isEmpty { detailedErrorMessage += "\nPath: \(path)" }

            case .dataCorrupted(let context):
                let path = context.codingPath.map { $0.stringValue }.joined(separator: " -> ")
                var finalPath = "root"
                if !path.isEmpty { finalPath = path }
                detailedErrorMessage += "The file data is corrupted near '\(finalPath)'."
                detailedErrorMessage += "\nDetails: \(context.debugDescription)"
                
            @unknown default:
                detailedErrorMessage += "An unknown decoding error occurred: \(error.localizedDescription)"
            }
        } else {
            detailedErrorMessage += "\n\n[Debug Info]\n\(error.localizedDescription)"
        }

        self.importErrorMessage = detailedErrorMessage
        self.showingImportErrorAlert = true
        print("Detailed decoding error: \(error)")
    }
    
    private func processNextImport() {
        guard let presetToImport = presetsToImport.first else {
            // No more presets to import, we are done.
            return
        }
        
        self.presetsToImport.removeFirst()
        
        if PresetManager.shared.presetExists(withId: presetToImport.id) {
            self.conflictingPreset = presetToImport
            self.showingImportConflictAlert = true
        } else {
            PresetManager.shared.addOrUpdatePreset(presetToImport)
            processNextImport() // Process the next preset in the list immediately.
        }
    }
}