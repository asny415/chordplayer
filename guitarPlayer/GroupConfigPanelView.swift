import SwiftUI

struct ChordButtonView: View {
    let chordName: String
    let isSelected: Bool
    let shortcut: String?
    let action: () -> Void
    
    private var displayName: (String, String) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Shortcut key overlay
                if let shortcut = shortcut {
                    Text(shortcut.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(5)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .frame(minWidth: 100, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.15))
            )
            // The "Glow" is an outer border that animates.
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 4)
                    .blur(radius: 4)
                    .opacity(isSelected ? 1 : 0) // Fade in/out
            )
            // A standard inner border for definition
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2),
                radius: isSelected ? 10 : 3, // Enhanced physicality
                x: 0,
                y: isSelected ? 5 : 1      // Enhanced physicality
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(isSelected ? 1.08 : 1.0) // Enhanced physicality
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isSelected)
    }
}

struct GroupConfigPanelView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer

    @FocusState private var groupNameFocused: Bool
    @FocusState private var chordSearchFocused: Bool
    @State private var chordSearchText: String = ""
    @State private var showChordEditSheet: Bool = false
    @State private var editingChordName: String = ""
    @State private var editingChordGroupIndex: Int? = nil
    @State private var editingShortcutBuffer: String = ""
    @State private var editingFingeringBuffer: String = ""
    @State private var showChordDiagramCreator: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Left: Group list
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

            Divider()

            // Right: Selected group editor
            VStack(alignment: .leading, spacing: 12) {
                // ensure the editor content doesn't get visually overlapped by the controlBar above
                if appData.performanceConfig.patternGroups.indices.contains(keyboardHandler.currentGroupIndex) {
                    let bindingGroupIndex = keyboardHandler.currentGroupIndex
                    let group = appData.performanceConfig.patternGroups[bindingGroupIndex]

                    HStack {
                        Text("Editing Group: \(group.name)")
                            .font(.title2)
                        Spacer()
                    }

                    // Group Name (was Default Pattern field)
                    VStack(alignment: .leading) {
                        Text("Group Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Group name", text: Binding(get: {
                            return appData.performanceConfig.patternGroups[bindingGroupIndex].name
                        }, set: { new in
                            appData.performanceConfig.patternGroups[bindingGroupIndex].name = new
                        }), onEditingChanged: { editing in
                            keyboardHandler.isTextInputActive = editing
                        })
                        .focused($groupNameFocused)
                        .onChange(of: groupNameFocused) { _, focused in
                            keyboardHandler.isTextInputActive = focused
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 360)
                    }

                    // Group-level defaults: Fingering and Drum Pattern (session only)
                    VStack(alignment: .leading, spacing: 12) {
                        // --- Chord management area ---
                        HStack {
                            Text("Chords")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                // Open chord diagram creator
                                showChordDiagramCreator = true
                            }) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }

                        // Add chord search and results (simple filtered list)
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

                            // Show limited results in a responsive grid so more chords are visible at once
                            ScrollView(.vertical, showsIndicators: true) {
                                // adaptive columns: will fit as many columns as space allows
                                let results = Array(filteredChordLibrary(prefix: chordSearchText).prefix(200))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                                    ForEach(results, id: \.self) { chord in
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
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                            Text(fingeringString)
                                                                .font(.system(.caption, design: .monospaced))
                                                                .tracking(-0.5)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                }
                                                Spacer()
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(.accentColor)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10).fill(.regularMaterial)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 6)
                            }
                            .frame(maxHeight: 220)
                            .background(FrameLogger(name: "searchResults"))
                        }

                        Divider()

                        // Chords grid for the group
                        VStack(alignment: .leading) {
                            Text("Group Chords")
                                .font(.headline)

                            if appData.performanceConfig.patternGroups.indices.contains(keyboardHandler.currentGroupIndex) {
                                let gi = keyboardHandler.currentGroupIndex
                                let group = appData.performanceConfig.patternGroups[gi]
                                ScrollView(.vertical) {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                                        ForEach(group.chordsOrder, id: \.self) { chordName in
                                            let shortcutDisplay = getShortcutForChord(chordName: chordName, group: group)
                                            ChordButtonView(chordName: chordName, isSelected: keyboardHandler.activeChordName == chordName, shortcut: shortcutDisplay) {
                                                // play chord with a simple pattern (pluck all strings once)
                                                let pattern: [MusicPatternEvent] = [MusicPatternEvent(delay: .double(0), notes: [1,2,3,4,5,6])]
                                                let keyName = appData.KEY_CYCLE.indices.contains(keyboardHandler.currentKeyIndex) ? appData.KEY_CYCLE[keyboardHandler.currentKeyIndex] : "C"
                                                guitarPlayer.playChord(chordName: chordName, pattern: pattern, tempo: keyboardHandler.currentTempo, key: keyName, velocity: UInt8(100))
                                            }
                                            .contextMenu {
                                                Button("Edit") {
                                                    editingChordName = chordName
                                                    editingChordGroupIndex = gi
                                                    editingShortcutBuffer = group.chordAssignments[chordName]?.shortcutKey ?? ""
                                                    showChordEditSheet = true
                                                }
                                                Button("Remove") {
                                                    removeChord(named: chordName, from: gi)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                                .padding(.top, 8)
                                .frame(maxHeight: 300)
                                .background(FrameLogger(name: "groupChords"))
                            } else {
                                Text("No group selected")
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack {
                            Text("Default Fingering")
                                .font(.headline)
                            Spacer()
                            Text("Based on global time signature: \(keyboardHandler.currentTimeSignature)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // NOTE: avoid mutating @Published properties during view body evaluation.
                        // Initialization of runtimeGroupSettings should happen in response to user actions or in setup code.
                        HStack(spacing: 12) {
                            Picker("Fingering", selection: Binding(get: {
                                appData.runtimeGroupSettings[bindingGroupIndex]?.fingeringId ?? appData.fingeringLibrary.first ?? ""
                            }, set: { new in
                                var settings = appData.runtimeGroupSettings[bindingGroupIndex] ?? GroupRuntimeSettings()
                                settings.fingeringId = new
                                appData.runtimeGroupSettings[bindingGroupIndex] = settings
                            })) {
                                ForEach(appData.fingeringLibrary, id: \.self) { f in
                                    Text(f).tag(f)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)

                            Button(action: {
                                // no-op preview placeholder for now
                            }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Preview fingering (not implemented)")
                        }

                        Divider()

                        
                    }
                } else {
                    Text("No group selected")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
        }
        .padding()
        .sheet(isPresented: $showChordEditSheet) {
            chordEditSheet
        }
        .sheet(isPresented: $showChordDiagramCreator) {
            ChordDiagramEditor(onSave: { name, def in
                appData.chordLibrary = appData.chordLibrary ?? [:]
                appData.chordLibrary?[name] = def
                // Add into current group if present
                addChord(to: keyboardHandler.currentGroupIndex, chordName: name)
                showChordDiagramCreator = false
            }, onCancel: {
                showChordDiagramCreator = false
            })
            .environmentObject(appData)
            .environmentObject(keyboardHandler)
        }
        .onChange(of: keyboardHandler.currentGroupIndex) { _, newIndex in
            guard appData.performanceConfig.patternGroups.indices.contains(newIndex) else { return }

            var settings = appData.runtimeGroupSettings[newIndex] ?? GroupRuntimeSettings()
            var changed = false

            // Ensure default fingering
            if settings.fingeringId == nil || settings.fingeringId!.isEmpty {
                if let defaultFingering = appData.fingeringLibrary.first {
                    settings.fingeringId = defaultFingering
                    changed = true
                }
            }

            

            if changed {
                appData.runtimeGroupSettings[newIndex] = settings
            }
        }
    }

    // MARK: - Chord Edit Sheet
    @ViewBuilder
    private var chordEditSheet: some View {
        if let gi = editingChordGroupIndex {
            let chordName = editingChordName
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Chord")
                    .font(.title2)

                Text("Chord: \(chordName)")

                VStack(alignment: .leading) {
                    Text("Shortcut Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter key", text: $editingShortcutBuffer, onEditingChanged: { editing in
                        keyboardHandler.isTextInputActive = editing
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                }

                VStack(alignment: .leading) {
                    Text("Fingering")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Fingering", selection: $editingFingeringBuffer) {
                        Text("(none)").tag("")
                        ForEach(appData.fingeringLibrary, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 240)
                }

                HStack {
                    Button("Save") {
                        if let gidx = editingChordGroupIndex {
                            var g = appData.performanceConfig.patternGroups[gidx]
                            var a = g.chordAssignments[editingChordName] ?? ChordAssignment()
                            a.shortcutKey = editingShortcutBuffer.isEmpty ? nil : editingShortcutBuffer
                            a.fingeringId = editingFingeringBuffer.isEmpty ? nil : editingFingeringBuffer
                            g.chordAssignments[editingChordName] = a
                            appData.performanceConfig.patternGroups[gidx] = g
                        }
                        showChordEditSheet = false
                        editingChordGroupIndex = nil
                    }
                    Button("Cancel") {
                        showChordEditSheet = false
                        editingChordGroupIndex = nil
                    }
                }
            }
            .padding()
            .frame(minWidth: 360)
            .onAppear {
                if appData.performanceConfig.patternGroups.indices.contains(gi) {
                    let g = appData.performanceConfig.patternGroups[gi]
                    let assign = g.chordAssignments[chordName]
                    editingShortcutBuffer = assign?.shortcutKey ?? ""
                    editingFingeringBuffer = assign?.fingeringId ?? ""
                }
            }
        } else {
            Text("No chord")
        }
    }

    private func getShortcutForChord(chordName: String, group: PatternGroup) -> String? {
        // 1. Check for a local, per-group override first.
        if let localShortcut = group.chordAssignments[chordName]?.shortcutKey, !localShortcut.isEmpty {
            return localShortcut.uppercased()
        }

        // 2. Check user-defined global keyMap.
        if let globalKey = appData.performanceConfig.keyMap.first(where: { $0.value == chordName })?.key {
            return globalKey.uppercased()
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
        let newGroup = PatternGroup(name: newName, patterns: ["__default__": nil])
        appData.performanceConfig.patternGroups.append(newGroup)
        keyboardHandler.currentGroupIndex = appData.performanceConfig.patternGroups.count - 1
    }

    private func removeGroup(at index: Int) {
        guard appData.performanceConfig.patternGroups.indices.contains(index) else { return }
        appData.performanceConfig.patternGroups.remove(at: index)
        keyboardHandler.currentGroupIndex = max(0, keyboardHandler.currentGroupIndex - 1)
    }

    private func addChord(to groupIndex: Int, chordName: String) {
        guard appData.performanceConfig.patternGroups.indices.contains(groupIndex) else { return }
        var group = appData.performanceConfig.patternGroups[groupIndex]
        // Avoid duplicates
        if group.chordsOrder.contains(chordName) { return }
        group.chordsOrder.append(chordName)
        group.chordAssignments[chordName] = ChordAssignment(fingeringId: nil, shortcutKey: nil)
        appData.performanceConfig.patternGroups[groupIndex] = group
    }

    private func removeChord(named chordName: String, from groupIndex: Int) {
        guard appData.performanceConfig.patternGroups.indices.contains(groupIndex) else { return }
        var group = appData.performanceConfig.patternGroups[groupIndex]
        group.chordsOrder.removeAll { $0 == chordName }
        group.chordAssignments.removeValue(forKey: chordName)
        appData.performanceConfig.patternGroups[groupIndex] = group
    }

    private func filteredChordLibrary(prefix: String) -> [String] {
        // Use the app's chordLibrary keys, fallback to empty list
        guard let library = appData.chordLibrary else { return [] }
        if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(library.keys).sorted()
        }
        let lower = prefix.lowercased()
        return library.keys.filter { $0.lowercased().contains(lower) }.sorted()
    }

    // MARK: - Small subviews
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
}