import SwiftUI
import CoreMIDI

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var metronome: Metronome

    @State private var showingCreateSheet = false
    @State private var activeGroupIndex: Int? = 0

    var body: some View {
        NavigationSplitView {
            // MARK: - Column 1: Sidebar for Presets
            PresetSidebar(showingCreateSheet: $showingCreateSheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)

        } content: {
            // MARK: - Column 2: Preset Workspace (Global Controls + Group List)
            PresetWorkspaceView(activeGroupIndex: $activeGroupIndex)
                .navigationSplitViewColumnWidth(min: 400, ideal: 450, max: 600)

        } detail: {
            // MARK: - Column 3: Group Config Panel (Inspector)
            GroupConfigPanelView(activeGroupIndex: $activeGroupIndex)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1200, minHeight: 700)
        .onAppear(perform: setupInitialState)
        .sheet(isPresented: $showingCreateSheet) {
            PresetCreateView()
        }
        // Clicking on empty area should clear focus so global shortcuts work again
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            keyboardHandler.isTextInputActive = false
        }
    }
    
    private func setupInitialState() {
        DispatchQueue.main.async {
            keyboardHandler.currentTimeSignature = appData.performanceConfig.timeSignature
            keyboardHandler.currentTempo = appData.performanceConfig.tempo
            
            let parts = appData.performanceConfig.timeSignature.split(separator: "/").map(String.init)
            if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                metronome.timeSignatureNumerator = num
                metronome.timeSignatureDenominator = den
            }
            metronome.tempo = appData.performanceConfig.tempo
        }
    }
}

// MARK: - Preset Sidebar View
private struct PresetSidebar: View {
    @EnvironmentObject var appData: AppData
    @StateObject private var presetManager = PresetManager.shared
    @Binding var showingCreateSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: .constant(presetManager.currentPreset?.id)) {
                Section(header: Text("Presets")) {
                    ForEach(presetManager.presets) { preset in
                        PresetRow(preset: preset,
                                  isCurrent: preset.id == presetManager.currentPreset?.id,
                                  onSelect: { appData.loadPreset(preset) })
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreateSheet = true }) {
                        Label("New Preset", systemImage: "plus")
                    }
                }
            }
            
            Divider()
            
            // Current Preset Status Footer
            VStack(alignment: .leading, spacing: 4) {
                let current = presetManager.currentPresetOrUnnamed
                let isUnnamed = presetManager.isUnnamedPreset(current)
                
                Text("Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: isUnnamed ? "circle.dotted" : "checkmark.circle.fill")
                        .foregroundColor(isUnnamed ? .orange : .green)
                    Text(current.name).bold()
                }
            }
            .padding()
        }
    }
}

// MARK: - Preset Row
private struct PresetRow: View {
    let preset: Preset
    let isCurrent: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text(preset.name)
                    .fontWeight(isCurrent ? .bold : .regular)
                if let desc = preset.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // Creating a more robust preview environment
        let midiManager = MidiManager()
        let metronome = Metronome(midiManager: midiManager)
        let appData = AppData()
        let guitarPlayer = GuitarPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
        let drumPlayer = DrumPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
        let keyboardHandler = KeyboardHandler(midiManager: midiManager, metronome: metronome, guitarPlayer: guitarPlayer, drumPlayer: drumPlayer, appData: appData)

        return ContentView()
            .environmentObject(appData)
            .environmentObject(midiManager)
            .environmentObject(metronome)
            .environmentObject(guitarPlayer)
            .environmentObject(drumPlayer)
            .environmentObject(keyboardHandler)
    }
}
