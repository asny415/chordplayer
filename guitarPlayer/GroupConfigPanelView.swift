import SwiftUI

// MARK: - Conflict Data Structure
struct ConflictData {
    let newChord: String
    let newShortcut: String
    let conflictingChords: [String]
    let groupIndex: Int
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
    
    private var displayName: (String, String) {
        if chordName.hasSuffix("_Major7") { let r = chordName.replacingOccurrences(of: "_Major7", with: "").replacingOccurrences(of: "_Sharp", with: "#"); return (r, "maj7") }
        if chordName.hasSuffix("_Minor7") { let r = chordName.replacingOccurrences(of: "_Minor7", with: "").replacingOccurrences(of: "_Sharp", with: "#"); return (r, "m7") }
        if chordName.hasSuffix("_Major") { let r = chordName.replacingOccurrences(of: "_Major", with: "").replacingOccurrences(of: "_Sharp", with: "#"); return (r, "") }
        if chordName.hasSuffix("_Minor") { let r = chordName.replacingOccurrences(of: "_Minor", with: "").replacingOccurrences(of: "_Sharp", with: "#"); return (r, "m") }
        let label = chordName.replacingOccurrences(of: "_Sharp", with: "#").replacingOccurrences(of: "_", with: " "); return (label, "")
    }
    
    var body: some View {
        Button(action: action) {
            VStack {
                Text(displayName.0)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                if !displayName.1.isEmpty {
                    Text(displayName.1)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
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
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    @Binding var activeGroupIndex: Int?
    
    @State private var showChordEditSheet: Bool = false
    @State private var editingChordName: String = ""
    @State private var showChordDiagramCreator: Bool = false
    @State private var capturingShortcutForChord: String? = nil
    @State private var showConflictAlert = false
    @State private var conflictData: ConflictData? = nil
    
    // State for the new Chord Library modal
    @State private var showChordLibrary = false

    var body: some View {
        groupEditorView
            .padding()
            .sheet(isPresented: $showChordEditSheet) { chordEditSheet }
            .sheet(isPresented: $showChordDiagramCreator) { chordDiagramCreatorSheet }
            .sheet(isPresented: $showChordLibrary) {
                ChordLibraryView { chordName in
                    if let groupIndex = activeGroupIndex {
                        addChord(to: groupIndex, chordName: chordName)
                    }
                    showChordLibrary = false // Dismiss after adding
                }
            }
            .onAppear(perform: setupOnAppear)
            .onDisappear { keyboardHandler.onShortcutCaptured = nil }
            .alert("Shortcut Conflict", isPresented: $showConflictAlert, presenting: conflictData) { data in
                Button("Replace (\(data.conflictingChords.joined(separator: ", ")))") {
                    resolveConflict(choice: .replace)
                }
                Button("Cancel", role: .cancel) {
                    resolveConflict(choice: .cancel)
                }
            } message: { data in
                Text("The shortcut \"\(ChordButtonView.formatShortcutDisplay(data.newShortcut))\" is already used by: \n\n\(data.conflictingChords.joined(separator: ", "))\n\nAssigning it to \"\(data.newChord)\" will remove it from the other chords.")
            }
            // Sync active group index with keyboard handler
            .onChange(of: activeGroupIndex) { _, newValue in
                keyboardHandler.currentGroupIndex = newValue ?? 0
            }
    }
    
    private func setupOnAppear() {
        keyboardHandler.currentGroupIndex = activeGroupIndex ?? 0
        setupShortcutCapture()
    }
    
    // MARK: - Sub Views
    private var groupEditorView: some View {
        ScrollView {
            if let groupIndex = activeGroupIndex, appData.performanceConfig.patternGroups.indices.contains(groupIndex) {
                VStack(alignment: .leading, spacing: 24) {
                    groupSettingsView(bindingGroupIndex: groupIndex)
                    chordManagementView(bindingGroupIndex: groupIndex)
                }
                .padding(.vertical)
            } else {
                Text("Select or create a group to begin.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func groupSettingsView(bindingGroupIndex: Int) -> some View {
        let groupBinding = $appData.performanceConfig.patternGroups[bindingGroupIndex]
        
        return Section(header: Text("Group Settings").font(.headline)) {
            TextField("Group Name", text: groupBinding.name)
            
            let patternsForTimeSig = appData.patternLibrary?[appData.performanceConfig.timeSignature] ?? []
            Picker("Default Fingering", selection: groupBinding.pattern) {
                Text("None").tag(String?.none)
                ForEach(patternsForTimeSig, id: \.id) {
                    p in
                    Text(p.name).tag(String?.some(p.id))
                }
            }
        }
    }
    
    private func chordManagementView(bindingGroupIndex: Int) -> some View {
        Section(header: Text("Assigned Chords").font(.headline)) {
            assignedChordsView(bindingGroupIndex: bindingGroupIndex)
            
            // Button to open the chord library
            Button(action: { showChordLibrary = true }) {
                Label("Add Chords from Library", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }
    
    private func assignedChordsView(bindingGroupIndex: Int) -> some View {
        let group = appData.performanceConfig.patternGroups[bindingGroupIndex]
        
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(group.chordAssignments.keys.sorted(), id: \.self) {
                    chordName in
                    assignedChordButton(chordName: chordName, group: group, bindingGroupIndex: bindingGroupIndex)
                }
            }
        }
    }
    
    private func assignedChordButton(chordName: String, group: PatternGroup, bindingGroupIndex: Int) -> some View {
        ChordButtonView(
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
            Button("Edit Details") {
                editingChordName = chordName
                showChordEditSheet = true
            }
            Button("Remove from Group", role: .destructive) {
                removeChord(from: bindingGroupIndex, chordName: chordName)
            }
        }
    }
    
    // MARK: - Sheet Views
    private var chordEditSheet: some View {
        // Simplified for brevity, logic remains the same
        if activeGroupIndex != nil {
            let chordName = editingChordName
            // This view should be built out more completely
            return AnyView(
                VStack {
                    Text("Edit Chord: \(chordName)").font(.title)
                    Text("Shortcut editing UI would go here.")
                    Spacer()
                    HStack {
                        Button("Cancel") { showChordEditSheet = false }
                        Button("Save") { /* Save logic here */ showChordEditSheet = false }
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
            if let groupIndex = activeGroupIndex {
                addChord(to: groupIndex, chordName: name)
            }
            showChordDiagramCreator = false
        }, onCancel: { showChordDiagramCreator = false })
    }
    
    // MARK: - Logic (Setup, Conflict, Helpers, etc.)
    
    private func setupShortcutCapture() {
        keyboardHandler.onShortcutCaptured = { (shortcut: String) in
            guard let chordName = capturingShortcutForChord, let groupIndex = activeGroupIndex else { return }
            
            let conflictingChords = findConflictingChords(for: shortcut, excluding: chordName, in: appData.performanceConfig.patternGroups[groupIndex])
            
            if conflictingChords.isEmpty {
                var config = appData.performanceConfig
                var group = config.patternGroups[groupIndex]
                var assignment = group.chordAssignments[chordName] ?? ChordAssignment()
                
                assignment.shortcutKey = shortcut
                group.chordAssignments[chordName] = assignment
                config.patternGroups[groupIndex] = group
                appData.performanceConfig = config
            } else {
                showConflictWarning(newChord: chordName, newShortcut: shortcut, conflictingChords: conflictingChords, groupIndex: groupIndex)
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
    
    private func showConflictWarning(newChord: String, newShortcut: String, conflictingChords: [String], groupIndex: Int) {
        self.conflictData = ConflictData(
            newChord: newChord,
            newShortcut: newShortcut,
            conflictingChords: conflictingChords,
            groupIndex: groupIndex
        )
        self.showConflictAlert = true
    }
    
    private func resolveConflict(choice: ConflictResolutionChoice) {
        guard let data = conflictData else { return }
        
        switch choice {
        case .replace:
            var config = appData.performanceConfig
            var group = config.patternGroups[data.groupIndex]

            // Remove shortcut from conflicting chords
            for chordName in data.conflictingChords {
                group.chordAssignments[chordName]?.shortcutKey = nil
            }
            
            // Assign shortcut to the new chord
            var assignment = group.chordAssignments[data.newChord] ?? ChordAssignment()
            assignment.shortcutKey = data.newShortcut
            group.chordAssignments[data.newChord] = assignment
            
            config.patternGroups[data.groupIndex] = group
            appData.performanceConfig = config

        case .cancel:
            break
        }
        conflictData = nil
    }

    private func addChord(to groupIndex: Int, chordName: String) {
        var config = appData.performanceConfig
        var group = config.patternGroups[groupIndex]
        if group.chordAssignments[chordName] == nil {
            group.chordAssignments[chordName] = ChordAssignment()
        }
        config.patternGroups[groupIndex] = group
        appData.performanceConfig = config
    }
    
    private func removeChord(from groupIndex: Int, chordName: String) {
        var config = appData.performanceConfig
        var group = config.patternGroups[groupIndex]
        group.chordAssignments.removeValue(forKey: chordName)
        config.patternGroups[groupIndex] = group
        appData.performanceConfig = config
    }
    
    private func getShortcutForChord(chordName: String, group: PatternGroup) -> String? {
        return group.chordAssignments[chordName]?.shortcutKey
    }
}
