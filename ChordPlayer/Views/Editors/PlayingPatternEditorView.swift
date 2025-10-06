import SwiftUI
import Combine

struct PlayingPatternEditorView: View {
    @Binding var pattern: GuitarPattern
    let isNew: Bool
    let onSave: (GuitarPattern) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var appData: AppData
    
    // State for the editor
    @State private var popoverStepIndex: Int? = nil
    @State private var selectedCell: (step: Int, string: Int)? = nil
    @State private var previewMidiChannel: Int = 1
    
    // State for fret input
    @State private var fretInputBuffer: String = ""
    @State private var fretInputCancellable: AnyCancellable?
    @State private var showingFretPopover: Bool = false
    @State private var fretOverrideValue: Int = 0

    @State private var showingDuplicateNameAlert = false
    @State private var duplicateName = ""

    var body: some View {
        VStack(spacing: 0) {
            headerView.padding()
            Divider()
            toolbarView.padding()
            gridEditorView.padding(.horizontal).padding(.bottom)
            Spacer()
            Divider()
            footerButtons.padding()
        }
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: 1200, minHeight: 500)
        .background(Color(.windowBackgroundColor))
        .onKeyDown { event in handleKeyDown(event) }
        .popover(isPresented: $showingFretPopover, arrowEdge: .bottom) {
            FretInputPopover(currentFret: $fretOverrideValue, onCommit: {
                commitFretOverride(fretOverrideValue)
                showingFretPopover = false
            })
        }
        .alert("Duplicate Pattern Name", isPresented: $showingDuplicateNameAlert) {
            Button("OK") { }
        } message: {
            Text("A pattern named '\(duplicateName)' already exists. Please choose a unique name.")
        }
    }

    // MARK: - Subviews
    private var headerView: some View {
        HStack {
            Text(isNew ? "Create Playing Pattern" : "Edit: \(pattern.name)")
                .font(.title).fontWeight(.bold)
            Spacer()
            HStack {
                TextField("Pattern Name", text: $pattern.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Auto") { pattern.name = pattern.generateAutomaticName() }
            }
            .frame(maxWidth: 300)
        }
    }

    private var lengthInBeats: Binding<Int> {
        Binding<Int>(
            get: {
                let timeSignature = appData.preset?.timeSignature ?? TimeSignature()
                let beatUnit = timeSignature.beatUnit > 0 ? timeSignature.beatUnit : 4
                // This is actually stepsPerQuarterNote
                let stepsPerQuarterNote = pattern.activeResolution.stepsPerBeat
                let actualStepsPerBeat = Double(stepsPerQuarterNote) * (4.0 / Double(beatUnit))
                
                guard actualStepsPerBeat > 0 else { return 0 }
                
                return Int(round(Double(pattern.length) / actualStepsPerBeat))
            },
            set: { newLengthInBeats in
                let timeSignature = appData.preset?.timeSignature ?? TimeSignature()
                let beatUnit = timeSignature.beatUnit > 0 ? timeSignature.beatUnit : 4
                let stepsPerQuarterNote = pattern.activeResolution.stepsPerBeat
                let actualStepsPerBeat = Double(stepsPerQuarterNote) * (4.0 / Double(beatUnit))
                
                let newLength = Int(round(Double(newLengthInBeats) * actualStepsPerBeat))
                pattern.length = max(1, newLength)
            }
        )
    }

    private var toolbarView: some View {
        HStack(spacing: 20) {
            Picker("Resolution", selection: $pattern.activeResolution) {
                ForEach(GridResolution.allCases) { res in Text(res.rawValue).tag(res) }
            }.pickerStyle(.menu)
            
            Stepper("Length: \(lengthInBeats.wrappedValue) beats", value: lengthInBeats, in: 1...64)
            
            Spacer()
            
            Picker("MIDI Ch:", selection: $previewMidiChannel) {
                ForEach(1...16, id: \.self) { channel in
                    Text("\(channel)").tag(channel)
                }
            }
            .frame(width: 120)

            Button("Preview with C Major") { 
                chordPlayer.previewPattern(pattern, midiChannel: previewMidiChannel)
            }
        }
    }

    private var gridEditorView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 4) {
                let labels = ["e", "B", "G", "D", "A", "E"]
                ForEach(0..<6) { i in
                    Text(labels[i])
                        .font(.system(.subheadline, design: .monospaced))
                        .frame(height: 35, alignment: .center)
                }
            }.padding(.trailing, 8).frame(width: 40)

            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(0..<pattern.steps.count, id: \.self) { index in
                        let stepsPerBeat = pattern.activeResolution.stepsPerBeat
                        VStack(spacing: 2) {
                            StepHeaderView(step: $pattern.steps[index], index: index, popoverStepIndex: $popoverStepIndex)
                            ForEach(0..<6, id: \.self) { stringIndex in
                                PatternGridCell(
                                    step: $pattern.steps[index],
                                    stringIndex: stringIndex,
                                    isSelected: selectedCell?.step == index && selectedCell?.string == stringIndex,
                                    onTap: { toggleCell(step: index, string: stringIndex) },
                                    onSetFretOverride: { showFretPopover(forStep: index, string: stringIndex) },
                                    onClearFretOverride: { clearFretOverride(forStep: index, string: stringIndex) }
                                )
                            }
                        }
                        .background((index / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        
                        if (index + 1) % stepsPerBeat == 0 && index < pattern.steps.count - 1 {
                            Divider().padding(.horizontal, 4)
                        }
                    }
                }.padding(.top, 5)
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
            Spacer()
            Button("Save", action: {
                // Validate for duplicate names
                guard let currentPreset = appData.preset else {
                    // Handle error: no current preset available
                    print("Error: No current preset available in AppData.")
                    onSave(pattern) // Or handle this error more gracefully
                    return
                }

                let existingPatterns = currentPreset.playingPatterns.filter { existingPattern in
                    // If editing, exclude the pattern itself from the duplicate check
                    if !isNew && existingPattern.id == pattern.id {
                        return false
                    }
                    return existingPattern.name == pattern.name
                }

                if !existingPatterns.isEmpty {
                    duplicateName = pattern.name
                    showingDuplicateNameAlert = true
                    return // Stop saving if duplicate name found
                }

                // If it's a new pattern and the name is still "New Pattern", auto-generate one
                if isNew && pattern.name == "New Pattern" {
                    pattern.name = pattern.generateAutomaticName()
                }
                onSave(pattern)
            }).buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Logic
    private func toggleCell(step: Int, string: Int) {
        selectedCell = (step, string)
        if pattern.steps[step].activeNotes.contains(string) {
            pattern.steps[step].activeNotes.remove(string)
            pattern.steps[step].fretOverrides.removeValue(forKey: string)
        } else {
            pattern.steps[step].activeNotes.insert(string)
        }
    }
    
    private func showFretPopover(forStep step: Int, string: Int) {
        selectedCell = (step, string)
        fretOverrideValue = pattern.steps[step].fretOverrides[string] ?? 0
        showingFretPopover = true
    }
    
    private func clearFretOverride(forStep step: Int, string: Int) {
        pattern.steps[step].fretOverrides.removeValue(forKey: string)
        selectedCell = (step, string)
    }
    
    private func commitFretOverride(_ fret: Int) {
        guard let selection = selectedCell else { return }
        guard pattern.steps[selection.step].activeNotes.contains(selection.string) else { return }
        pattern.steps[selection.step].fretOverrides[selection.string] = fret
    }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Check if text field is currently focused - if so, don't handle custom keyboard events
        if let currentFirstResponder = NSApp.keyWindow?.firstResponder,
           currentFirstResponder is NSTextField || 
           currentFirstResponder is NSTextView {
            // Text field or text view is focused, allow normal text input processing
            return false
        }
        
        guard let selection = selectedCell else { return false }
        
        switch event.keyCode {
        case 51: // Backspace/Delete
            clearFretOverride(forStep: selection.step, string: selection.string)
            return true
        default:
            if let chars = event.characters, let _ = Int(chars) {
                fretInputCancellable?.cancel()
                fretInputBuffer += chars
                
                if fretInputBuffer.count >= 2 {
                    commitFretInput()
                } else {
                    fretInputCancellable = Just(()).delay(for: .milliseconds(400), scheduler: DispatchQueue.main).sink { [self] in commitFretInput() }
                }
                return true
            }
            return false
        }
    }
    
    private func commitFretInput() {
        if let fret = Int(fretInputBuffer), (0...24).contains(fret) {
            commitFretOverride(fret)
        }
        fretInputBuffer = ""
        fretInputCancellable = nil
    }
}

// MARK: - Subviews

private struct PatternGridCell: View {
    @Binding var step: PatternStep
    let stringIndex: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onSetFretOverride: () -> Void
    let onClearFretOverride: () -> Void
    
    private var isActive: Bool { step.activeNotes.contains(stringIndex) }
    private var fretOverride: Int? { step.fretOverrides[stringIndex] }
    private var technique: PlayingTechnique? { step.techniques[stringIndex] }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(cellColor)
                .frame(width: 30, height: 35)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2))

            VStack(spacing: 1) {
                if let fret = fretOverride {
                    Text(String(fret))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                } else if isActive {
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 8, height: 8)
                }
                
                if let tech = technique {
                    Text(tech.symbol)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.top, fretOverride == nil && isActive ? 4 : 0)
                }
            }
        }
        .onTapGesture(perform: onTap)
        .contextMenu {
            if isActive {
                Button("Set Fret Override...", action: onSetFretOverride)
                if fretOverride != nil {
                    Button("Clear Fret Override", action: onClearFretOverride)
                }
                Divider()
                Menu("Set Technique...") {
                    ForEach(PlayingTechnique.allCases) { tech in
                        Button(tech.chineseName) {
                            step.techniques[stringIndex] = tech
                        }
                    }
                }
                if technique != nil {
                    Button("Clear Technique") {
                        step.techniques.removeValue(forKey: stringIndex)
                    }
                }
            }
        }
    }
    
    private var cellColor: Color {
        if isActive {
            if technique != nil {
                return .orange
            }
            return fretOverride != nil ? .purple : .accentColor
        } else {
            return .primary.opacity(0.2)
        }
    }
}

private struct StepHeaderView: View {
    @Binding var step: PatternStep
    let index: Int
    @Binding var popoverStepIndex: Int?

    var body: some View {
        Button(action: { self.popoverStepIndex = self.index }) {
            VStack {
                stepTypeIcon.font(.system(size: 14))
                Text("\(index + 1)").font(.caption).foregroundColor(.secondary)
            }
            .frame(width: 30, height: 35)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .popover(isPresented: .constant(popoverStepIndex == index), arrowEdge: .bottom) {
            StepPopoverView(step: $step, popoverStepIndex: $popoverStepIndex)
        }
    }
    
    @ViewBuilder private var stepTypeIcon: some View {
        switch step.type {
        case .rest: Image(systemName: "minus").foregroundColor(.secondary)
        case .arpeggio: Image(systemName: "wavy.lines.up.and.down").foregroundColor(.blue)
        case .strum: Image(systemName: step.strumDirection == .down ? "arrow.down" : "arrow.up").foregroundColor(.green)
        }
    }
}

private struct StepPopoverView: View {
    @Binding var step: PatternStep
    @Binding var popoverStepIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(popoverStepIndex.map { String($0 + 1) } ?? "") Settings").font(.headline)
            Picker("Type", selection: $step.type) {
                ForEach(StepType.allCases) { type in Text(type.rawValue).tag(type) }
            }.pickerStyle(SegmentedPickerStyle())

            if step.type == .strum {
                Picker("Direction", selection: $step.strumDirection) {
                    ForEach(StrumDirection.allCases) { dir in Text(dir.rawValue).tag(dir) }
                }.pickerStyle(SegmentedPickerStyle())
                Picker("Speed", selection: $step.strumSpeed) {
                    ForEach(StrumSpeed.allCases) { speed in Text(speed.rawValue).tag(speed) }
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { popoverStepIndex = nil }
            }
        }.padding().frame(minWidth: 250)
    }
}