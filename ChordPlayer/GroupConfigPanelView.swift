import SwiftUI

// MARK: - Conflict Data Structure
struct ConflictData {
    let newChord: String
    let newShortcut: String
    let conflictingChords: [String]
    let groupId: UUID
}

enum ConflictResolutionChoice {
    case replace
    case cancel
}

// MARK: - Chord Button View
struct ChordButtonView: View {
    let chordName: String
    let isSelected: Bool
    let shortcut: String?
    let action: () -> Void // For playing the chord
    let onShortcutClick: (String) -> Void // For initiating shortcut capture
    let isCapturingShortcut: Bool // To indicate if this button is currently capturing
    
    private var displayString: String {
        let name = chordName.replacingOccurrences(of: "_Sharp", with: "#")
        let parts = name.split(separator: "_")

        if parts.count == 2 {
            let note = String(parts[0])
            let quality = String(parts[1])

            if quality == "Major" {
                return note
            } else if quality == "Minor" {
                return note + "m"
            }
        }
        
        // Fallback for other names like "C_Major_7" or custom names
        return name.replacingOccurrences(of: "_", with: " ")
    }
    
    var body: some View {
        Button(action: action) {
            Text(displayString)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .frame(minWidth: 100, minHeight: 70)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                .overlay(alignment: .topTrailing) {
                    shortcutView
                }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var shortcutView: some View {
        Button(action: { onShortcutClick(chordName) }) {
            if let shortcut = shortcut, !shortcut.isEmpty {
                Text(ChordButtonView.formatShortcutDisplay(shortcut))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.2))
                    .foregroundColor(.white.opacity(0.8))
                    .cornerRadius(4)
                    .padding(4)
            } else {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .opacity(isCapturingShortcut ? 0.5 : 1.0)
    }
    
    static func formatShortcutDisplay(_ shortcut: String) -> String {
        if shortcut.contains("⌘") || shortcut.contains("⌃") || shortcut.contains("⌥") || shortcut.contains("⇧") { return shortcut }
        return shortcut.uppercased()
    }
}

// MARK: - Main Panel View
struct GroupConfigPanelView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    @Binding var activeGroupId: UUID?
    
    @State private var showChordEditSheet: Bool = false
    @State private var editingChordName: String = ""
    @State private var showChordDiagramCreator: Bool = false
    @State private var capturingShortcutForChord: String? = nil
    @State private var showConflictAlert = false
    @State private var conflictData: ConflictData? = nil
    
    // State for the new Chord Library modal
    @State private var showChordLibrary = false
    @State private var showCustomChordCreator = false

    var body: some View {
        groupEditorView
            .padding()
            .sheet(isPresented: $showChordEditSheet) { chordEditSheet }
            .sheet(isPresented: $showChordDiagramCreator) { chordDiagramCreatorSheet }
            .sheet(isPresented: $showChordLibrary) {
                ChordLibraryView(
                    onAddChord: { chordName in
                        if let activeGroupId = activeGroupId {
                            addChord(to: activeGroupId, chordName: chordName)
                        }
                    },
                    existingChordNames: Set(appData.performanceConfig.patternGroups.first(where: { $0.id == activeGroupId })?.chordAssignments.keys.map { $0 } ?? [])
                )
            }
            .sheet(isPresented: $showCustomChordCreator) {
                CustomChordCreatorView()
                    .environmentObject(appData)
                    .environmentObject(chordPlayer)
                    .environmentObject(keyboardHandler)
            }
            .onAppear(perform: setupOnAppear)
            .onDisappear { keyboardHandler.onShortcutCaptured = nil }
            .alert("group_config_panel_shortcut_conflict_alert_title", isPresented: $showConflictAlert, presenting: conflictData) { data in
                Button(String(format: "group_config_panel_replace_button_format", arguments: [data.conflictingChords.joined(separator: ", ")])) {
                    resolveConflict(choice: .replace)
                }
                Button("group_config_panel_cancel_button", role: .cancel) {
                    resolveConflict(choice: .cancel)
                }
            } message: { data in
                Text(String(format: "group_config_panel_shortcut_conflict_message_format", arguments: [ChordButtonView.formatShortcutDisplay(data.newShortcut), data.conflictingChords.joined(separator: ", "), data.newChord]))
            }
            // Sync active group index with keyboard handler
            // .onChange(of: activeGroupId) { _, newValue in
            //     keyboardHandler.currentGroupIndex = newValue ?? 0
            // }
    }
    
    private func setupOnAppear() {
        // keyboardHandler.currentGroupIndex = activeGroupId ?? 0
        setupShortcutCapture()
    }
    
    // MARK: - Sub Views
    private var groupEditorView: some View {
        ScrollView {
            if let activeGroupId = activeGroupId, let groupBinding = $appData.performanceConfig.patternGroups.first(where: { $0.id == activeGroupId }) {
                VStack(alignment: .leading, spacing: 24) {
                    groupSettingsView(groupBinding: groupBinding)
                    chordManagementView(groupBinding: groupBinding)
                }
                .padding(.vertical)
            } else {
                Text("group_config_panel_select_or_create_group_placeholder")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func groupSettingsView(groupBinding: Binding<PatternGroup>) -> some View {
        return Section(header: Text("group_config_panel_group_settings_header").font(.headline)) {
            let patternsForTimeSig = appData.patternLibrary?[appData.performanceConfig.timeSignature] ?? []
            Picker("group_config_panel_default_fingering_picker_label", selection: groupBinding.pattern) {
                Text("group_config_panel_none_option").tag(String?.none)
                ForEach(patternsForTimeSig, id: \.id) {
                    p in
                    Text(p.name).tag(String?.some(p.id))
                }
            }
        }
    }
    
    private func chordManagementView(groupBinding: Binding<PatternGroup>) -> some View {
        Section(header: Text("已分配的和弦").font(.headline)) {
            assignedChordsView(groupBinding: groupBinding)
            
            // 和弦管理按钮组
            HStack(spacing: 12) {
                Button(action: { showChordLibrary = true }) {
                    Label("从和弦库添加", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: { showCustomChordCreator = true }) {
                    Label("创建自定义和弦", systemImage: "star.circle.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)
        }
    }
    
    private func assignedChordsView(groupBinding: Binding<PatternGroup>) -> some View {
        let group = groupBinding.wrappedValue
        
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(group.chordAssignments.keys.sorted(), id: \.self) {
                    chordName in
                    assignedChordButton(chordName: chordName, groupBinding: groupBinding)
                }
            }
        }
    }
    
    private func assignedChordButton(chordName: String, groupBinding: Binding<PatternGroup>) -> some View {
        let group = groupBinding.wrappedValue
        return ChordButtonView(
            chordName: chordName,
            isSelected: keyboardHandler.activeChordName == chordName,
            shortcut: getShortcutForChord(chordName: chordName, group: group),
            action: { keyboardHandler.playChordButton(chordName: chordName) },
            onShortcutClick: { chordName in
                capturingShortcutForChord = chordName
                keyboardHandler.startCapturingShortcut(for: chordName)
            },
            isCapturingShortcut: capturingShortcutForChord == chordName
        )
        .contextMenu {
            Button("group_config_panel_edit_details_context_menu") {
                editingChordName = chordName
                showChordEditSheet = true
            }
            Button("group_config_panel_remove_from_group_context_menu", role: .destructive) {
                let currentGroupId = groupBinding.wrappedValue.id
                removeChord(from: currentGroupId, chordName: chordName)
            }
        }
    }
    
    // MARK: - Sheet Views
    private var chordEditSheet: some View {
        // Simplified for brevity, logic remains the same
        if activeGroupId != nil {
            let chordName = editingChordName
            // This view should be built out more completely
            return AnyView(
                VStack {
                    Text(String(format: "group_config_panel_edit_chord_sheet_title_format", arguments: [chordName])).font(.title)
                    Text("group_config_panel_shortcut_editing_ui_placeholder")
                    Spacer()
                    HStack {
                        Button("group_config_panel_sheet_cancel_button") { showChordEditSheet = false }
                        Button("group_config_panel_sheet_save_button") { /* Save logic here */ showChordEditSheet = false }
                    }
                }.padding().frame(width: 400, height: 300)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private var chordDiagramCreatorSheet: some View {
        ChordDiagramEditor(onSave: { name, def in
            appData.chordLibrary = appData.chordLibrary ?? [:]
            appData.chordLibrary?[name] = def
            if let activeGroupId = activeGroupId {
                addChord(to: activeGroupId, chordName: name)
            }
            showChordDiagramCreator = false
        }, onCancel: { showChordDiagramCreator = false })
    }
    
    // MARK: - Logic (Setup, Conflict, Helpers, etc.)
    
    private func setupShortcutCapture() {
        keyboardHandler.onShortcutCaptured = { (chordName: String, shortcut: String) in
            guard let activeGroupId = activeGroupId, let groupIndex = appData.performanceConfig.patternGroups.firstIndex(where: { $0.id == activeGroupId }) else { return }
            let group = appData.performanceConfig.patternGroups[groupIndex]

            let conflictingChords = findConflictingChords(for: shortcut, excluding: chordName, in: group)

            if conflictingChords.isEmpty {
                var config = appData.performanceConfig
                var groupToModify = config.patternGroups[groupIndex]
                var assignment = groupToModify.chordAssignments[chordName] ?? ChordAssignment()

                assignment.shortcutKey = shortcut
                groupToModify.chordAssignments[chordName] = assignment
                config.patternGroups[groupIndex] = groupToModify
                appData.performanceConfig = config
            } else {
                showConflictWarning(newChord: chordName, newShortcut: shortcut, conflictingChords: conflictingChords, groupId: activeGroupId)
            }

            capturingShortcutForChord = nil
            keyboardHandler.stopCapturingShortcut()
        }
    }
    
    private func findConflictingChords(for shortcut: String, excluding chordToExclude: String, in group: PatternGroup) -> [String] {
        return group.chordAssignments.filter { (chordName, assignment) in
            return chordName != chordToExclude && assignment.shortcutKey == shortcut
        }.map { $0.key }
    }
    
    private func showConflictWarning(newChord: String, newShortcut: String, conflictingChords: [String], groupId: UUID) {
        self.conflictData = ConflictData(
            newChord: newChord,
            newShortcut: newShortcut,
            conflictingChords: conflictingChords,
            groupId: groupId
        )
        self.showConflictAlert = true
    }
    
    private func resolveConflict(choice: ConflictResolutionChoice) {
        guard let data = conflictData, let groupIndex = appData.performanceConfig.patternGroups.firstIndex(where: { $0.id == data.groupId }) else { return }
        
        switch choice {
        case .replace:
            var config = appData.performanceConfig
            var group = config.patternGroups[groupIndex]

            // Remove shortcut from conflicting chords
            for chordName in data.conflictingChords {
                group.chordAssignments[chordName]?.shortcutKey = nil
            }
            
            // Assign shortcut to the new chord
            var assignment = group.chordAssignments[data.newChord] ?? ChordAssignment()
            assignment.shortcutKey = data.newShortcut
            group.chordAssignments[data.newChord] = assignment
            
            config.patternGroups[groupIndex] = group
            appData.performanceConfig = config

        case .cancel:
            break
        }
        conflictData = nil
    }

    private func addChord(to groupId: UUID, chordName: String) {
        guard let groupIndex = appData.performanceConfig.patternGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var config = appData.performanceConfig
        var group = config.patternGroups[groupIndex]
        if group.chordAssignments[chordName] == nil {
            group.chordAssignments[chordName] = ChordAssignment()
        }
        config.patternGroups[groupIndex] = group
        appData.performanceConfig = config
    }
    
    private func removeChord(from groupId: UUID, chordName: String) {
        guard let groupIndex = appData.performanceConfig.patternGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var config = appData.performanceConfig
        var group = config.patternGroups[groupIndex]
        group.chordAssignments.removeValue(forKey: chordName)
        config.patternGroups[groupIndex] = group
        appData.performanceConfig = config
    }
    
    private func getShortcutForChord(chordName: String, group: PatternGroup) -> String? {
        // First, check for an assigned shortcut key
        if let assignedShortcut = group.chordAssignments[chordName]?.shortcutKey, !assignedShortcut.isEmpty {
            return assignedShortcut
        }
        // If no assigned shortcut, try to get the default shortcut from KeyboardHandler
        return keyboardHandler.getDefaultShortcutDisplay(for: chordName)
    }
}