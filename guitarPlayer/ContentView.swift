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


// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @FocusState private var groupNameFocused: Bool
    
    let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    var body: some View {
    ZStack {
            // Main background color
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Top Control Bar
                controlBar
                    .padding()
                    .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // MARK: - Group Configuration Panel
                groupConfigPanel
            }
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
            }
            .frame(minWidth: 220, maxWidth: 280)
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)

            Divider()

            // Right: Selected group editor
            VStack(alignment: .leading, spacing: 12) {
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

                    // Simple chord list for this group (string keys in patterns map, excluding __default__)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Chords in Group")
                                .font(.headline)
                            Spacer()
                            Button(action: { addChordEntry(to: bindingGroupIndex) }) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(appData.performanceConfig.patternGroups[bindingGroupIndex].patterns.keys.filter { $0 != "__default__" }.sorted()), id: \.self) { chordKey in
                                    HStack {
                                        Text(chordKey)
                                            .font(.body)
                                        Spacer()
                                        TextField("pattern name", text: Binding(get: {
                                            if let optional = appData.performanceConfig.patternGroups[bindingGroupIndex].patterns[chordKey], let value = optional {
                                                return value
                                            }
                                            return ""
                                        }, set: { new in
                                            appData.performanceConfig.patternGroups[bindingGroupIndex].patterns[chordKey] = new.isEmpty ? nil : new
                                        }), onEditingChanged: { editing in
                                            keyboardHandler.isTextInputActive = editing
                                        })
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 240)
                                        Button(action: {
                                            appData.performanceConfig.patternGroups[bindingGroupIndex].patterns.removeValue(forKey: chordKey)
                                        }) {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
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
#Preview {
    // Creating a more robust preview environment
    let midiManager = MidiManager()
    let metronome = Metronome(midiManager: midiManager)
    let appData = AppData()
    let guitarPlayer = GuitarPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
    let drumPlayer = DrumPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
    let keyboardHandler = KeyboardHandler(midiManager: midiManager, metronome: metronome, guitarPlayer: guitarPlayer, drumPlayer: drumPlayer, appData: appData)
    
    ContentView()
        .environmentObject(appData)
        .environmentObject(midiManager)
        .environmentObject(metronome)
        .environmentObject(guitarPlayer)
        .environmentObject(drumPlayer)
        .environmentObject(keyboardHandler)
}
