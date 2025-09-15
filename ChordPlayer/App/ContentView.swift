import SwiftUI
import CoreMIDI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    var body: some View {
        NavigationSplitView {
            PresetSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            // TODO: This view needs to be refactored to use the new data model
            PresetWorkspaceView()
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear(perform: setupInitialState)
        // All .sheet modifiers for custom libraries are removed as they are now obsolete.
        // The functionality will be integrated into the PresetWorkspaceView.
    }

    private func setupInitialState() {
        DispatchQueue.main.async {
            // TODO: keyboardHandler needs to be updated to work with the new Preset model
            // keyboardHandler.updateWithNewConfig(appData.preset)
        }
    }
}

private struct PresetSidebar: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var presetManager: PresetManager
    @State private var editingPresetId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: .constant(presetManager.currentPreset?.id)) {
                Section(header: Text("Presets")) { // Using literal string for now
                    ForEach(presetManager.presets) { presetInfo in
                        PresetRow(
                            presetInfo: presetInfo,
                            isCurrent: presetInfo.id == presetManager.currentPreset?.id,
                            onSelect: { appData.loadPreset(presetInfo) },
                            isEditing: .constant(editingPresetId == presetInfo.id),
                            onRename: { newName in
                                presetManager.renamePreset(presetInfo, newName: newName)
                                editingPresetId = nil
                            },
                            onStartEditing: { presetId in
                                editingPresetId = presetId
                            }
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {                        
                        let newPresetName = "New Preset \(Date().formatted(.dateTime.month().day().hour().minute().second()))"
                        appData.createNewPreset(name: newPresetName)
                        // The new preset is automatically loaded, we can grab its ID for editing.
                        if let newPresetId = presetManager.currentPreset?.id {
                            editingPresetId = newPresetId
                        }
                    }) {
                        Label("New Preset", systemImage: "plus.circle")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Current Preset")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let current = presetManager.currentPreset {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(current.name).bold()
                    }
                } else {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.yellow)
                        Text("No Preset Loaded").bold()
                    }
                }
            }
            .padding()
        }
    }
}

private struct PresetRow: View {
    @EnvironmentObject var presetManager: PresetManager
    let presetInfo: PresetInfo
    let isCurrent: Bool
    let onSelect: () -> Void
    @Binding var isEditing: Bool
    let onRename: (String) -> Void
    let onStartEditing: (UUID) -> Void

    @State private var showingDeleteConfirmation = false
    @State private var newName: String = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                if isEditing {
                    TextField("Preset Name", text: $newName, onCommit: {
                        onRename(newName)
                        isNameFieldFocused = false
                    })
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onAppear {
                        newName = presetInfo.name
                        isNameFieldFocused = true
                    }
                } else {
                    Text(presetInfo.name)
                        .fontWeight(isCurrent ? .bold : .regular)
                }
                // Description was removed from PresetInfo, so this is commented out
                // if let desc = presetInfo.description, !desc.isEmpty {
                //     Text(desc).font(.caption).foregroundColor(.secondary)
                // }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onSelect() } }
        .highPriorityGesture(TapGesture(count: 2).onEnded { onStartEditing(presetInfo.id) })
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Preset", systemImage: "trash")
            }
        }
        .alert("Delete Preset", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { presetManager.deletePreset(presetInfo) }
        } message: {
            Text("Are you sure you want to delete \"\(presetInfo.name)\"? This action cannot be undone.")
        }
    }
}