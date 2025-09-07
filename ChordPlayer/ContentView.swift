
import SwiftUI
import CoreMIDI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var metronome: Metronome

    @Binding var showCustomChordCreatorFromMenu: Bool
    @Binding var showCustomChordManagerFromMenu: Bool
    @Binding var showAddDrumPatternSheet: Bool
    @Binding var showAddPlayingPatternSheet: Bool

    var body: some View {
        NavigationSplitView {
            PresetSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
        } detail: {
            PresetWorkspaceView()
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear(perform: setupInitialState)
        .sheet(isPresented: $showCustomChordCreatorFromMenu) {
            CustomChordCreatorView()
        }
        .sheet(isPresented: $showCustomChordManagerFromMenu) {
            CustomChordLibraryView()
        }
        .sheet(isPresented: $showAddDrumPatternSheet) {
            AddDrumPatternSheetView()
        }
        .sheet(isPresented: $showAddPlayingPatternSheet) {
            AddPlayingPatternSheetView()
        }
    }

    private func setupInitialState() {
        DispatchQueue.main.async {
            keyboardHandler.updateWithNewConfig(appData.performanceConfig)
            metronome.update(from: appData.performanceConfig)
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
                Section(header: Text("content_view_presets_section_header")) {
                    ForEach(presetManager.presets) { preset in
                        PresetRow(
                            preset: preset,
                            isCurrent: preset.id == presetManager.currentPreset?.id,
                            onSelect: { appData.loadPreset(preset) },
                            isEditing: .constant(editingPresetId == preset.id),
                            onRename: { newName in
                                presetManager.renamePreset(preset, newName: newName)
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
                        let newPresetName = String(localized: "content_view_new_preset_prefix") + " \(Date().formatted(.dateTime.month().day().hour().minute().second()))"
                        if let newPreset = appData.createNewPreset(name: newPresetName) {
                            editingPresetId = newPreset.id
                        }
                    }) {
                        Label("content_view_new_preset_button", systemImage: "plus.circle")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                let current = presetManager.currentPresetOrUnnamed
                let isUnnamed = presetManager.isUnnamedPreset(current)

                Text("content_view_current_preset_label")
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

private struct PresetRow: View {
    @EnvironmentObject var presetManager: PresetManager
    let preset: Preset
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
                    TextField("content_view_preset_name_placeholder", text: $newName, onCommit: {
                        onRename(newName)
                        isNameFieldFocused = false
                    })
                    .textFieldStyle(.plain)
                    .focused($isNameFieldFocused)
                    .onAppear {
                        newName = preset.name
                        isNameFieldFocused = true
                    }
                } else {
                    Text(preset.name)
                        .fontWeight(isCurrent ? .bold : .regular)
                }
                if let desc = preset.description, !desc.isEmpty {
                    Text(desc).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !isEditing { onSelect() } }
        .highPriorityGesture(TapGesture(count: 2).onEnded { onStartEditing(preset.id) })
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("content_view_delete_preset_context_menu", systemImage: "trash")
            }
        }
        .alert("content_view_delete_preset_alert_title", isPresented: $showingDeleteConfirmation) {
            Button("content_view_cancel_button", role: .cancel) { }
            Button("content_view_delete_button", role: .destructive) { presetManager.deletePreset(preset) }
        } message: {
            Text(String(format: "content_view_delete_preset_confirmation_message", preset.name))
        }
    }
}
