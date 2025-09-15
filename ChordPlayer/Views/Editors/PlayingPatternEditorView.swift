import SwiftUI

struct PlayingPatternEditorView: View {
    @Binding var pattern: GuitarPattern
    let isNew: Bool
    let onSave: (GuitarPattern) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var chordPlayer: ChordPlayer
    
    @State private var popoverStepIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding()
            
            Divider()
            
            toolbarView
                .padding()

            gridEditorView
                .padding(.horizontal)
                .padding(.bottom)

            Spacer()
            
            Divider()
            
            footerButtons
                .padding()
        }
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: 1200, minHeight: 500)
        .background(Color(.windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            Text(isNew ? "Create Playing Pattern" : "Edit: \(pattern.name)")
                .font(.title).fontWeight(.bold)
            Spacer()
            HStack {
                TextField("Pattern Name", text: $pattern.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Auto") {
                    pattern.name = pattern.generateAutomaticName()
                }
            }
            .frame(maxWidth: 300)
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 20) {
            // Control for Resolution
            Picker("Resolution", selection: $pattern.resolution) {
                ForEach(NoteResolution.allCases) { res in
                    Text(res.rawValue).tag(res)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 200)

            // Control for Length
            Stepper("Length: \(pattern.length) steps", value: $pattern.length, in: 1...64)
            
            Spacer()
            
            Button("Preview with C Major") {
                chordPlayer.previewPattern(pattern)
            }
        }
    }

    private var gridEditorView: some View {
        HStack(spacing: 0) {
            // String labels on the left
            VStack(alignment: .trailing, spacing: 4) {
                let labels = ["e", "B", "G", "D", "A", "E"]
                ForEach(0..<6) { i in
                    Text(labels[i])
                        .font(.system(.subheadline, design: .monospaced))
                        .frame(height: 35, alignment: .center)
                }
            }
            .padding(.trailing, 8)
            .frame(width: 40)

            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(0..<pattern.steps.count, id: \.self) { index in
                        let stepsPerBeat = pattern.resolution == .sixteenth ? 4 : 2
                        VStack(spacing: 2) {
                            StepHeaderView(step: $pattern.steps[index], index: index, popoverStepIndex: $popoverStepIndex)
                            
                            ForEach(0..<6, id: \.self) { stringIndex in
                                gridCell(stepIndex: index, stringIndex: stringIndex)
                            }
                        }
                        .background((index / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                        
                        if (index + 1) % stepsPerBeat == 0 && index < pattern.steps.count - 1 {
                            Divider().padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.top, 5)
            }
        }
    }
    
    private func gridCell(stepIndex: Int, stringIndex: Int) -> some View {
        let isActive = pattern.steps[stepIndex].activeNotes.contains(stringIndex)
        return Rectangle()
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.2))
            .frame(width: 30, height: 35)
            .cornerRadius(4)
            .onTapGesture {
                if isActive {
                    pattern.steps[stepIndex].activeNotes.remove(stringIndex)
                } else {
                    pattern.steps[stepIndex].activeNotes.insert(stringIndex)
                }
            }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
            Spacer()
            Button("Save", action: {
                // Auto-name only if it's a new pattern with the default name.
                if isNew && pattern.name == "New Pattern" {
                    pattern.name = pattern.generateAutomaticName()
                }
                onSave(pattern)
            }).buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Subviews for Editor

private struct StepHeaderView: View {
    @Binding var step: PatternStep
    let index: Int
    @Binding var popoverStepIndex: Int?

    var body: some View {
        Button(action: { self.popoverStepIndex = self.index }) {
            VStack {
                stepTypeIcon
                    .font(.system(size: 14))
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    
    @ViewBuilder
    private var stepTypeIcon: some View {
        switch step.type {
        case .rest:
            Image(systemName: "minus")
                .foregroundColor(.secondary)
        case .arpeggio:
            Image(systemName: "wavy.lines.up.and.down")
                .foregroundColor(.blue)
        case .strum:
            Image(systemName: step.strumDirection == .down ? "arrow.down" : "arrow.up")
                .foregroundColor(.green)
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
                ForEach(StepType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            if step.type == .strum {
                Picker("Direction", selection: $step.strumDirection) {
                    ForEach(StrumDirection.allCases) { dir in
                        Text(dir.rawValue).tag(dir)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Picker("Speed", selection: $step.strumSpeed) {
                    ForEach(StrumSpeed.allCases) { speed in
                        Text(speed.rawValue).tag(speed)
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Done") { popoverStepIndex = nil }
            }
        }
        .padding()
        .frame(minWidth: 250)
    }
}

extension String {
    subscript(i: Int) -> String {
        return String(self[index(startIndex, offsetBy: i)])
    }
}
