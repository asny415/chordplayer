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

struct ChordButtonView: View {
    let chordName: String
    let isSelected: Bool
    let shortcut: String?
    let action: () -> Void // For playing the chord
    let onShortcutClick: (String) -> Void // For initiating shortcut capture
    let isCapturingShortcut: Bool // To indicate if this button is currently capturing
    
    private var displayName: (String, String) {
        if chordName.hasSuffix("_Major7") {
            let root = chordName.replacingOccurrences(of: "_Major7", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Major7")
        }
        if chordName.hasSuffix("_Minor7") {
            let root = chordName.replacingOccurrences(of: "_Minor7", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Minor7")
        }
        if chordName.hasSuffix("_Major") {
            let root = chordName.replacingOccurrences(of: "_Major", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Major")
        }
        if chordName.hasSuffix("_Minor") {
            let root = chordName.replacingOccurrences(of: "_Minor", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Minor")
        }
        
        var label = chordName.replacingOccurrences(of: "_Sharp", with: "#")
        label = label.replacingOccurrences(of: "_", with: " ")
        return (label, "")
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Main content
                VStack {
                    Text(displayName.0)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    if !displayName.1.isEmpty {
                        Text(displayName.1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .frame(minWidth: 120, minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                )
                
                // Shortcut key overlay / Placeholder (now always a button)
                Button(action: { onShortcutClick(chordName) }) {
                    ZStack {
                        if let shortcut = shortcut {
                            Text(ChordButtonView.formatShortcutDisplay(shortcut))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(5)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Circle())
                                .padding(4)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(5)
                                .background(Color.black.opacity(0.25))
                                .clipShape(Circle())
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .opacity(isCapturingShortcut ? 0.5 : 1.0)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Shortcut Display Formatting
    static func formatShortcutDisplay(_ shortcut: String) -> String {
        // If the shortcut already contains modifier symbols, return as is
        if shortcut.contains("⌘") || shortcut.contains("⌃") || shortcut.contains("⌥") || shortcut.contains("⇧") {
            return shortcut
        }
        
        // For backward compatibility, if it's a simple key without modifiers, just uppercase it
        return shortcut.uppercased()
    }
}

struct GroupConfigPanelView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    @FocusState private var groupNameFocused: Bool
    @FocusState private var chordSearchFocused: Bool
    @State private var chordSearchText: String = ""
    @State private var showChordEditSheet: Bool = false
    @State private var editingChordName: String = ""
    @State private var editingChordGroupIndex: Int? = nil
    @State private var editingShortcutBuffer: String = ""
    @State private var editingFingeringBuffer: String = ""
    @State private var showChordDiagramCreator: Bool = false
    @State private var capturingShortcutForChord: String? = nil
    @State private var showConflictAlert = false
    @State private var conflictData: ConflictData? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                groupListView
                Divider()
                groupEditorView
            }
        }
        .sheet(isPresented: $showChordEditSheet) {
            chordEditSheet
        }
        .sheet(isPresented: $showChordDiagramCreator) {
            chordDiagramCreatorSheet
        }
        .onAppear {
            setupShortcutCapture()
        }
        .onDisappear {
            keyboardHandler.onShortcutCaptured = nil
        }
        .alert("快捷键冲突", isPresented: $showConflictAlert) {
            conflictAlertButtons
        } message: {
            conflictAlertMessage
        }
    }
    
    // MARK: - Sub Views
    private var groupListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Groups")
                    .font(.headline)
                Spacer()
                Button(action: addGroup) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(appData.performanceConfig.patternGroups.enumerated()), id: \.offset) { index, group in
                        GroupRow(group: group, isSelected: index == keyboardHandler.currentGroupIndex) {
                            keyboardHandler.currentGroupIndex = index
                        } onRename: { newName in
                            appData.performanceConfig.patternGroups[index].name = newName
                        } onDelete: {
                            removeGroup(at: index)
                        }
                    }
                }
                .padding(4)
            }
            .background(FrameLogger(name: "leftGroupList"))
        }
        .frame(minWidth: 220, maxWidth: 280)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var groupEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appData.performanceConfig.patternGroups.indices.contains(keyboardHandler.currentGroupIndex) {
                let bindingGroupIndex = keyboardHandler.currentGroupIndex
                let group = appData.performanceConfig.patternGroups[bindingGroupIndex]

                groupHeaderView(group: group, bindingGroupIndex: bindingGroupIndex)
                groupSettingsView(bindingGroupIndex: bindingGroupIndex)
                chordManagementView(bindingGroupIndex: bindingGroupIndex)
            } else {
                Text("No groups available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    private func groupHeaderView(group: PatternGroup, bindingGroupIndex: Int) -> some View {
        HStack {
            Text("Editing Group: \(group.name)")
                .font(.title2)
            Spacer()
        }
    }
    
    private func groupSettingsView(bindingGroupIndex: Int) -> some View {
        HStack(spacing: 16) {
            // Group Name TextField
            TextField("Group name", text: Binding(get: {
                appData.performanceConfig.patternGroups[bindingGroupIndex].name
            }, set: { new in
                appData.performanceConfig.patternGroups[bindingGroupIndex].name = new
            }), onEditingChanged: { editing in
                keyboardHandler.isTextInputActive = editing
            })
            .focused($groupNameFocused)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onAppear {
                DispatchQueue.main.async {
                    groupNameFocused = false
                }
            }

            // Default Fingering Picker
            let patternsForTimeSig = appData.patternLibrary?[appData.performanceConfig.timeSignature] ?? []
            Picker("Default Fingering", selection: Binding(get: {
                appData.performanceConfig.patternGroups[bindingGroupIndex].pattern ?? patternsForTimeSig.first?.id ?? ""
            }, set: { new in
                appData.performanceConfig.patternGroups[bindingGroupIndex].pattern = new
            })) {
                ForEach(patternsForTimeSig, id: \.id) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.menu)
            
            Spacer()
        }
        .padding()
        .background(Color.black.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func chordManagementView(bindingGroupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // --- Chord management area ---
            HStack {
                Text("Chords")
                    .font(.headline)
                Spacer()
                Button(action: {
                    showChordDiagramCreator = true
                }) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }

            chordSearchAndResultsView(bindingGroupIndex: bindingGroupIndex)
            assignedChordsView(bindingGroupIndex: bindingGroupIndex)
        }
    }
    
    private func chordSearchAndResultsView(bindingGroupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Search chords...", text: $chordSearchText, onEditingChanged: { editing in
                keyboardHandler.isTextInputActive = editing
            })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 360)
                .focused($chordSearchFocused)
                .onChange(of: chordSearchFocused) { _old, focused in
                    keyboardHandler.isTextInputActive = focused
                }
                .background(FrameLogger(name: "searchTextField"))

            chordResultsGridView(bindingGroupIndex: bindingGroupIndex)
        }
    }
    
    private func chordResultsGridView(bindingGroupIndex: Int) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            let results = Array(filteredChordLibrary(prefix: chordSearchText).prefix(200))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(results, id: \.self) { chord in
                    chordResultButton(chord: chord, bindingGroupIndex: bindingGroupIndex)
                }
            }
            .padding(4)
        }
        .frame(maxHeight: 300)
        .background(FrameLogger(name: "chordResultsGrid"))
    }
    
    private func chordResultButton(chord: String, bindingGroupIndex: Int) -> some View {
        Button(action: {
            addChord(to: keyboardHandler.currentGroupIndex, chordName: chord)
        }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(chord)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    let fingeringArray = appData.chordLibrary?[chord] ?? []
                    let fingeringString = fingeringArray.map { item -> String in
                        switch item {
                        case .string(let s):
                            return s
                        case .int(let i):
                            return String(i)
                        }
                    }.joined(separator: "·")

                    if !fingeringString.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "guitars")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(fingeringString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func assignedChordsView(bindingGroupIndex: Int) -> some View {
        let group = appData.performanceConfig.patternGroups[bindingGroupIndex]
        
        if group.chordAssignments.isEmpty {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Assigned Chords")
                    .font(.headline)

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(Array(group.chordAssignments.keys.sorted()), id: \.self) { chordName in
                            assignedChordButton(
                                chordName: chordName,
                                group: group,
                                bindingGroupIndex: bindingGroupIndex
                            )
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 200)
                .background(FrameLogger(name: "assignedChordsGrid"))
            }
        )
    }
    
    private func assignedChordButton(chordName: String, group: PatternGroup, bindingGroupIndex: Int) -> some View {
        ChordButtonView(
            chordName: chordName,
            isSelected: false,
            shortcut: getShortcutForChord(chordName: chordName, group: group),
            action: {
                keyboardHandler.playChordButton(chordName: chordName)
            },
            onShortcutClick: { chordName in
                capturingShortcutForChord = chordName
                keyboardHandler.startCapturingShortcut(for: chordName)
            },
            isCapturingShortcut: capturingShortcutForChord == chordName
        )
        .contextMenu {
            Button("Edit") {
                editingChordGroupIndex = bindingGroupIndex
                editingChordName = chordName
                showChordEditSheet = true
            }
            Button("Remove", role: .destructive) {
                removeChord(from: bindingGroupIndex, chordName: chordName)
            }
        }
    }
    
    // MARK: - Sheet Views
    private var chordEditSheet: some View {
        if let gi = editingChordGroupIndex {
            let chordName = editingChordName
            let group = appData.performanceConfig.patternGroups[gi]
            let assignment = group.chordAssignments[chordName] ?? ChordAssignment()
            
            return AnyView(
                VStack(spacing: 20) {
                    Text("Edit Chord: \(chordName)")
                        .font(.title2)
                        .padding()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Shortcut Key Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shortcut Key")
                                .font(.headline)
                            
                            HStack {
                                if let currentShortcut = assignment.shortcutKey, !currentShortcut.isEmpty {
                                    Text("Current: \(ChordButtonView.formatShortcutDisplay(currentShortcut))")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No shortcut assigned")
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    capturingShortcutForChord = chordName
                                    keyboardHandler.startCapturingShortcut(for: chordName)
                                }) {
                                    Text(capturingShortcutForChord == chordName ? "Press key..." : "Set Shortcut")
                                }
                                .disabled(capturingShortcutForChord != nil)
                            }
                        }
                        
                        // Fingering Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fingering Pattern")
                                .font(.headline)
                            
                            TextField("Pattern ID", text: $editingFingeringBuffer)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onAppear {
                                    editingFingeringBuffer = assignment.fingeringId ?? ""
                                }
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    HStack {
                        Button("Cancel") {
                            showChordEditSheet = false
                            editingChordGroupIndex = nil
                            editingChordName = ""
                        }
                        
                        Spacer()
                        
                        Button("Save") {
                            var updatedGroup = appData.performanceConfig.patternGroups[gi]
                            var updatedAssignment = updatedGroup.chordAssignments[chordName] ?? ChordAssignment()
                            updatedAssignment.fingeringId = editingFingeringBuffer.isEmpty ? nil : editingFingeringBuffer
                            updatedGroup.chordAssignments[chordName] = updatedAssignment
                            appData.performanceConfig.patternGroups[gi] = updatedGroup
                            
                            showChordEditSheet = false
                            editingChordGroupIndex = nil
                            editingChordName = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
                .frame(width: 400, height: 300)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private var chordDiagramCreatorSheet: some View {
        ChordDiagramEditor(onSave: { name, def in
            appData.chordLibrary = appData.chordLibrary ?? [:]
            appData.chordLibrary?[name] = def
            addChord(to: keyboardHandler.currentGroupIndex, chordName: name)
            showChordDiagramCreator = false
        }, onCancel: {
            showChordDiagramCreator = false
        })
        .environmentObject(appData)
        .environmentObject(keyboardHandler)
    }
    
    // MARK: - Alert Views
    @ViewBuilder
    private var conflictAlertButtons: some View {
        if let data = conflictData {
            Button("替换 (\(data.conflictingChords.joined(separator: ", ")))") {
                resolveConflict(choice: .replace)
            }
            Button("取消", role: .cancel) {
                resolveConflict(choice: .cancel)
            }
        }
    }
    
    @ViewBuilder
    private var conflictAlertMessage: some View {
        if let data = conflictData {
            Text("快捷键 \"\(ChordButtonView.formatShortcutDisplay(data.newShortcut))\" 已经被以下和弦使用：\n\n\(data.conflictingChords.joined(separator: ", "))\n\n选择 \"替换\" 将移除这些和弦的快捷键，并分配给 \"\(data.newChord)\"。")
        }
    }
    
    // MARK: - Setup Methods
    private func setupShortcutCapture() {
        keyboardHandler.onShortcutCaptured = { chordName, capturedKey in
            let gi = self.keyboardHandler.currentGroupIndex
            guard self.appData.performanceConfig.patternGroups.indices.contains(gi) else { return }

            // Check for conflicts before setting the shortcut
            if !capturedKey.isEmpty {
                let conflictingChords = self.findConflictingChords(
                    for: capturedKey, 
                    excluding: chordName, 
                    in: self.appData.performanceConfig.patternGroups[gi]
                )
                
                if !conflictingChords.isEmpty {
                    self.showConflictWarning(
                        newChord: chordName,
                        newShortcut: capturedKey,
                        conflictingChords: conflictingChords,
                        groupIndex: gi
                    )
                    self.capturingShortcutForChord = nil
                    return
                }
            }

            var group = self.appData.performanceConfig.patternGroups[gi]
            var assignment = group.chordAssignments[chordName] ?? ChordAssignment()
            assignment.shortcutKey = capturedKey.isEmpty ? nil : capturedKey
            group.chordAssignments[chordName] = assignment
            self.appData.performanceConfig.patternGroups[gi] = group

            self.capturingShortcutForChord = nil
        }
    }

    // MARK: - Conflict Detection and Resolution
    private func findConflictingChords(for shortcut: String, excluding excludeChord: String, in group: PatternGroup) -> [String] {
        var conflicts: [String] = []
        
        for (chordName, assignment) in group.chordAssignments {
            if chordName != excludeChord && assignment.shortcutKey == shortcut {
                conflicts.append(chordName)
            }
        }
        
        return conflicts
    }
    
    private func showConflictWarning(newChord: String, newShortcut: String, conflictingChords: [String], groupIndex: Int) {
        conflictData = ConflictData(
            newChord: newChord,
            newShortcut: newShortcut,
            conflictingChords: conflictingChords,
            groupIndex: groupIndex
        )
        showConflictAlert = true
    }
    
    private func resolveConflict(choice: ConflictResolutionChoice) {
        guard let data = conflictData else { return }
        
        switch choice {
        case .replace:
            // Remove shortcut from conflicting chords and assign to new chord
            var group = appData.performanceConfig.patternGroups[data.groupIndex]
            
            // Remove shortcuts from conflicting chords
            for chordName in data.conflictingChords {
                if var assignment = group.chordAssignments[chordName] {
                    assignment.shortcutKey = nil
                    group.chordAssignments[chordName] = assignment
                }
            }
            
            // Assign shortcut to new chord
            var newAssignment = group.chordAssignments[data.newChord] ?? ChordAssignment()
            newAssignment.shortcutKey = data.newShortcut
            group.chordAssignments[data.newChord] = newAssignment
            
            appData.performanceConfig.patternGroups[data.groupIndex] = group
            
        case .cancel:
            // Do nothing, just close the alert
            break
        }
        
        // Clean up
        conflictData = nil
        showConflictAlert = false
    }

    // MARK: - Helper Methods
    private func filteredChordLibrary(prefix: String) -> [String] {
        let allChords = Array(appData.chordLibrary?.keys ?? [String: [StringOrInt]]().keys)
        if prefix.isEmpty {
            return allChords.sorted()
        }
        return allChords.filter { $0.localizedCaseInsensitiveContains(prefix) }.sorted()
    }
    
    private func addChord(to groupIndex: Int, chordName: String) {
        guard appData.performanceConfig.patternGroups.indices.contains(groupIndex) else { return }
        
        var group = appData.performanceConfig.patternGroups[groupIndex]
        if group.chordAssignments[chordName] == nil {
            group.chordAssignments[chordName] = ChordAssignment()
            appData.performanceConfig.patternGroups[groupIndex] = group
        }
    }
    
    private func removeChord(from groupIndex: Int, chordName: String) {
        guard appData.performanceConfig.patternGroups.indices.contains(groupIndex) else { return }
        
        var group = appData.performanceConfig.patternGroups[groupIndex]
        group.chordAssignments.removeValue(forKey: chordName)
        appData.performanceConfig.patternGroups[groupIndex] = group
    }
    
    private func getShortcutForChord(chordName: String, group: PatternGroup) -> String? {
        // 1. Check for a local, per-group override first.
        if let localShortcut = group.chordAssignments[chordName]?.shortcutKey, !localShortcut.isEmpty {
            return localShortcut
        }

        // 2. Check user-defined global keyMap.
        if let globalKey = appData.performanceConfig.keyMap.first(where: { $0.value == chordName })?.key {
            return globalKey
        }

        // 3. Fallback to the default, hardcoded mapping from MusicTheory.
        if let defaultShortcut = MusicTheory.defaultChordToShortcutMap[chordName] {
            return defaultShortcut
        }

        // 4. No shortcut found.
        return nil
    }

    // MARK: - Group Helpers
    private func addGroup() {
        let newName = "New Group \(appData.performanceConfig.patternGroups.count + 1)"
        var initialPattern: String? = nil
        if let patternsForTimeSig = appData.patternLibrary?[appData.performanceConfig.timeSignature],
           let firstPattern = patternsForTimeSig.first {
            initialPattern = firstPattern.id
        } else if let fallbackPattern = appData.patternLibrary?["4/4"]?.first {
            initialPattern = fallbackPattern.id
        }
        
        let newGroup = PatternGroup(
            name: newName,
            patterns: [:],
            pattern: initialPattern,
            chordAssignments: [:]
        )
        appData.performanceConfig.patternGroups.append(newGroup)
        keyboardHandler.currentGroupIndex = appData.performanceConfig.patternGroups.count - 1
    }
    
    private func removeGroup(at index: Int) {
        guard appData.performanceConfig.patternGroups.indices.contains(index) else { return }
        appData.performanceConfig.patternGroups.remove(at: index)
        
        // Adjust current group index if necessary
        if keyboardHandler.currentGroupIndex >= appData.performanceConfig.patternGroups.count {
            keyboardHandler.currentGroupIndex = max(0, appData.performanceConfig.patternGroups.count - 1)
        }
    }
}

// MARK: - GroupRow View
struct GroupRow: View {
    var group: PatternGroup
    var isSelected: Bool
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Text(group.name)
                        .foregroundColor(isSelected ? .white : .primary)
                    if isSelected {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(isSelected ? Color.blue.opacity(0.25) : Color.clear)
        .cornerRadius(6)
    }
}