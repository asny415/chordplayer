import SwiftUI
import CoreMIDI

// MARK: - Reusable Views

struct ControlStripLabel: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, -2)
    }
}

struct StyledPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let items: [T]
    let display: (T) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ControlStripLabel(title: title)
            Picker(title, selection: $selection) {
                ForEach(items, id: \.self) { item in
                    Text(display(item)).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.15))
            .cornerRadius(8)
            .accentColor(.cyan)
        }
    }
}

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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: isSelected ? 8 : 3, x: 0, y: isSelected ? 4 : 1)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}

// Simple debug helper: prints the global frame of the view it's attached to.
struct FrameLogger: View {
    let name: String
    @State private var lastFrame: CGRect = .zero
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    let f = geo.frame(in: .global)
                    print("[FrameLogger] \(name) onAppear frame=\(f)")
                    lastFrame = f
                }
                .onReceive(Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()) { _ in
                    let f = geo.frame(in: .global)
                    if f != lastFrame {
                        lastFrame = f
                        print("[FrameLogger] \(name) changed frame=\(f)")
                    }
                }
        }
    }
}


// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
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
    
    let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    var body: some View {
    ZStack {
            // Main background color
            Color.black.opacity(0.9).ignoresSafeArea()
            
                VStack(alignment: .leading, spacing: 10) {
                // MARK: - Top Control Bar
                controlBar
                    .padding()
                    .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // MARK: - Group Configuration Panel
                groupConfigPanel
                                .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600) // Increased minWidth for more horizontal space
        .onAppear(perform: setupInitialState)
        // Clicking on empty area should clear focus so global shortcuts work again
        .contentShape(Rectangle())
        .onTapGesture {
            groupNameFocused = false
            keyboardHandler.isTextInputActive = false
        }
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
    }
}

    // MARK: - Control Bar View
    private var controlBar: some View {
        HStack(spacing: 16) {
            // MIDI Output
            StyledPicker(
                title: "MIDI Output",
                selection: $midiManager.selectedOutput,
                items: [nil] + midiManager.availableOutputs,
                display: { endpoint in
                    // Provide a clear label when no endpoint is selected
                    endpoint.map { midiManager.displayName(for: $0) } ?? "None"
                }
            )
            .frame(width: 160)
            .disabled(midiManager.availableOutputs.isEmpty) // disable when no outputs
            
            // Pickers Group
            HStack(spacing: 12) {
                StyledPicker(title: "Key", selection: Binding(get: { keyboardHandler.currentKeyIndex }, set: { keyboardHandler.currentKeyIndex = $0 }), items: Array(0..<keys.count)) { keys[$0] }
                
                StyledPicker(title: "Time Sig", selection: Binding(get: { keyboardHandler.currentTimeSignature }, set: { keyboardHandler.currentTimeSignature = $0 }), items: appData.TIME_SIGNATURE_CYCLE) { $0 }

                StyledPicker(title: "Group", selection: Binding(get: { keyboardHandler.currentGroupIndex }, set: { keyboardHandler.currentGroupIndex = $0 }), items: Array(0..<appData.performanceConfig.patternGroups.count)) { appData.performanceConfig.patternGroups[$0].name }
                
                StyledPicker(title: "Quantize", selection: Binding(get: { keyboardHandler.quantizationMode }, set: { keyboardHandler.quantizationMode = $0; appData.performanceConfig.quantize = $0 }), items: QuantizationMode.allCases.map { $0.rawValue }) { $0 }
            }
            
            Spacer()
            
            // Tempo Control
            VStack(alignment: .leading, spacing: 4) {
                ControlStripLabel(title: "BPM: \(Int(keyboardHandler.currentTempo))")
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { keyboardHandler.currentTempo }, set: { keyboardHandler.currentTempo = $0; metronome.tempo = $0 }), in: 60...240, step: 1)
                    Stepper("BPM", value: Binding(get: { keyboardHandler.currentTempo }, set: { keyboardHandler.currentTempo = $0; metronome.tempo = $0 }), in: 60...240, step: 1).labelsHidden()
                }
            }
            .frame(width: 180)
            
            // Drum Machine Toggle
            VStack(spacing: 4) {
                ControlStripLabel(title: "Drum Machine")
                Button(action: {
                    if drumPlayer.isPlaying {
                        drumPlayer.stop()
                    } else {
                        drumPlayer.playPattern(patternName: "ROCK_4_4_BASIC", tempo: keyboardHandler.currentTempo, timeSignature: keyboardHandler.currentTimeSignature, velocity: 100, durationMs: 200)
                    }
                }) {
                    Image(systemName: drumPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(drumPlayer.isPlaying ? .red : .green)
                }
                .disabled(midiManager.availableOutputs.isEmpty && !drumPlayer.isPlaying) // disable play when no MIDI output available
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .focusable(false)
        .background(FrameLogger(name: "controlBar"))
    }
    
    // MARK: - Group Configuration Panel
    private var groupConfigPanel: some View {
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
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(chord)
                                                        .font(.subheadline)
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                    // optional secondary info placeholder
                                                    Text("Add to group")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
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
                                            let assign = group.chordAssignments[chordName]
                                            ChordButtonView(chordName: chordName, isSelected: false, shortcut: assign?.shortcutKey) {
                                                // play chord with a simple pattern (pluck all strings once)
                                                let pattern: [MusicPatternEvent] = [MusicPatternEvent(delay: .double(0), notes: [1,2,3,4,5,6])]
                                                let keyName = appData.KEY_CYCLE.indices.contains(keyboardHandler.currentKeyIndex) ? appData.KEY_CYCLE[keyboardHandler.currentKeyIndex] : "C"
                                                guitarPlayer.playChord(chordName: chordName, pattern: pattern, tempo: keyboardHandler.currentTempo, key: keyName, velocity: UInt8(100))
                                            }
                                            .contextMenu {
                                                Button("Edit") {
                                                    editingChordName = chordName
                                                    editingChordGroupIndex = gi
                                                    editingShortcutBuffer = assign?.shortcutKey ?? ""
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
                                appData.runtimeGroupSettings[bindingGroupIndex]?.fingeringId ?? ""
                            }, set: { new in
                                var settings = appData.runtimeGroupSettings[bindingGroupIndex] ?? GroupRuntimeSettings()
                                settings.fingeringId = new.isEmpty ? nil : new
                                appData.runtimeGroupSettings[bindingGroupIndex] = settings
                            })) {
                                Text("(none)").tag("")
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

                        HStack {
                            Text("Default Drum Pattern")
                                .font(.headline)
                            Spacer()
                            Text("Based on global time signature: \(keyboardHandler.currentTimeSignature)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Picker("Drum Pattern", selection: Binding(get: {
                                appData.runtimeGroupSettings[bindingGroupIndex]?.drumPatternId ?? ""
                            }, set: { new in
                                var settings = appData.runtimeGroupSettings[bindingGroupIndex] ?? GroupRuntimeSettings()
                                settings.drumPatternId = new.isEmpty ? nil : new
                                appData.runtimeGroupSettings[bindingGroupIndex] = settings
                            })) {
                                Text("(none)").tag("")
                                if let drums = appData.drumPatternLibrary {
                                    ForEach(drums.keys.sorted(), id: \.self) { key in
                                        Text(key).tag(key)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)

                            Button(action: {
                                // Play quick drum preview if desired
                                if let pid = appData.runtimeGroupSettings[bindingGroupIndex]?.drumPatternId {
                                    drumPlayer.playPattern(patternName: pid, tempo: keyboardHandler.currentTempo, timeSignature: keyboardHandler.currentTimeSignature, velocity: 100, durationMs: 800)
                                }
                            }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Preview drum pattern")
                        }
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

    private func addChordEntry(to groupIndex: Int) {
        guard appData.performanceConfig.patternGroups.indices.contains(groupIndex) else { return }
        // Add a placeholder chord key so user can edit it
        var i = 1
        var key = "NEW_CHORD_\(i)"
        while appData.performanceConfig.patternGroups[groupIndex].patterns.keys.contains(key) {
            i += 1
            key = "NEW_CHORD_\(i)"
        }
        appData.performanceConfig.patternGroups[groupIndex].patterns[key] = nil
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
    
    // MARK: - Setup
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
