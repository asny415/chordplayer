import SwiftUI
import CoreMIDI

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var metronome: Metronome

    @State private var activeGroupIndex: Int? = 0

    var body: some View {
        NavigationSplitView {
            // MARK: - Column 1: Sidebar for Presets
            PresetSidebar()
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
    @EnvironmentObject var presetManager: PresetManager // Changed from @StateObject
    @State private var editingPresetId: UUID? // New state for inline editing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: .constant(presetManager.currentPreset?.id)) {
                Section(header: Text("Presets")) {
                    ForEach(presetManager.presets) { preset in
                        PresetRow(preset: preset,
                                  isCurrent: preset.id == presetManager.currentPreset?.id,
                                  onSelect: { appData.loadPreset(preset) },
                                  isEditing: .constant(editingPresetId == preset.id),
                                  onRename: { newName in
                                      presetManager.renamePreset(preset, newName: newName)
                                      editingPresetId = nil // Exit editing mode
                                  },
                                  onStartEditing: { presetId in
                                      editingPresetId = presetId // Set editing mode for the double-clicked preset
                                  })
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let newPresetName = "New Preset " + Date().formatted(date: .numeric, time: .standard)
                        if let newPreset = appData.createNewPreset(name: newPresetName) {
                            editingPresetId = newPreset.id // Set editing mode for the new preset
                        }
                    } label: {
                        Label("New Preset", systemImage: "plus.circle")
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
    @EnvironmentObject var presetManager: PresetManager
    let preset: Preset
    let isCurrent: Bool
    let onSelect: () -> Void
    @Binding var isEditing: Bool // New binding for editing state
    let onRename: (String) -> Void // New closure for renaming
    let onStartEditing: (UUID) -> Void // New closure to start editing from double-click
    
    @State private var showingDeleteConfirmation = false
    @State private var newName: String = "" // State for TextField
    
    @FocusState private var isNameFieldFocused: Bool // For auto-focusing TextField
    
    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                if isEditing {
                    TextField("Preset Name", text: $newName, onCommit: {
                        onRename(newName)
                        isNameFieldFocused = false // Resign focus on commit
                    })
                    .textFieldStyle(.plain)
                    .font(isCurrent ? .headline : .body)
                    .focused($isNameFieldFocused) // Apply focus state
                    .onAppear {
                        newName = preset.name // Initialize TextField with current name
                        DispatchQueue.main.async { // Delay focus to ensure TextField is ready
                            isNameFieldFocused = true
                        }
                    }
                    .onChange(of: isEditing) { newValue in
                        if newValue { // If editing starts, focus the field
                            DispatchQueue.main.async { // Delay focus to ensure TextField is ready
                                isNameFieldFocused = true
                            }
                        }
                    }
                } else {
                    Text(preset.name)
                        .fontWeight(isCurrent ? .bold : .regular)
                }
                if let desc = preset.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: {
            if !isEditing {
                onSelect()
            }
        })
        .highPriorityGesture(TapGesture(count: 2).onEnded { // Double tap to edit
            onStartEditing(preset.id)
        })
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
        }
        .alert("Delete Preset", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _ = presetManager.deletePreset(preset)
            }
        } message: {
            Text("Are you sure you want to delete '\(preset.name)'? This action cannot be undone.")
        }
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
            .environmentObject(PresetManager.shared)
    }
}
