
import SwiftUI
import AppKit

// MARK: - Main Editor View

struct MelodicLyricEditorView: View {
    @EnvironmentObject private var appData: AppData
    @EnvironmentObject private var midiManager: MidiManager
    @EnvironmentObject private var midiSequencer: MIDISequencer
    @EnvironmentObject private var melodicLyricPlayer: MelodicLyricPlayer
    @Binding var segment: MelodicLyricSegment

    // Editor State
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var gridSizeInSteps: Int = 1 // 16th notes by default
    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedStep: Int = 0
    @State private var editingWordStep: Int? = nil
    @State private var editingWord: String = ""
    @State private var isTechniqueUpdateInternal = false
    @State private var keyMonitor: Any?
    @State private var lastPreviewNote: UInt8? = nil
    
    @State private var editorMidiChannel: Int = 1
    
    // In-place name editing state
    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isInlineEditorFocused: Bool

    // Layout constants
    private let beatWidth: CGFloat = 120
    private let beatsPerBar: Int = 4
    private let stepsPerBeat: Int = 4
    private var totalSteps: Int { segment.lengthInBars * beatsPerBar * stepsPerBeat }
    private var stepWidth: CGFloat { (beatWidth / CGFloat(stepsPerBeat)) * zoomLevel }
    private let trackHeight: CGFloat = 120

    init(segment: Binding<MelodicLyricSegment>) {
        self._segment = segment
        self._selectedStep = State(initialValue: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. In-place Editable Title
            HStack {
                Spacer()
                if isEditingName {
                    TextField("Segment Name", text: $segment.name)
                        .font(.largeTitle).textFieldStyle(.plain).multilineTextAlignment(.center)
                        .focused($isNameFieldFocused)
                        .onSubmit { isEditingName = false }.onDisappear { isEditingName = false }
                } else {
                    Text(segment.name).font(.largeTitle).fontWeight(.bold)
                        .onTapGesture(count: 2) { isEditingName = true; isNameFieldFocused = true }
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal)
            .padding(.bottom, 4)

            // 2. Toolbar
            MelodicLyricToolbar(
                currentTechnique: $currentTechnique,
                gridSizeInSteps: $gridSizeInSteps,
                zoomLevel: $zoomLevel,
                segmentLengthInBars: $segment.lengthInBars,
                midiChannel: $editorMidiChannel,
                isPlayingSegment: $melodicLyricPlayer.isPlaying,
                onTogglePlayback: toggleSegmentPlayback
            ).padding().background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            // 3. Main Content Editor
            ScrollView([.horizontal]) {
                ZStack(alignment: .topLeading) {
                    // Layer 1: Background Grid
                    MelodicLyricGridBackground(
                        lengthInBars: segment.lengthInBars, beatsPerBar: beatsPerBar, beatWidth: beatWidth,
                        trackHeight: trackHeight, zoomLevel: zoomLevel, stepsPerBeat: stepsPerBeat,
                        gridSizeInSteps: gridSizeInSteps
                    )

                    if melodicLyricPlayer.isPlaying {
                        let totalBeats = Double(segment.lengthInBars * beatsPerBar)
                        // Ensure we don't divide by zero and stay within bounds
                        let progress = totalBeats > 0 ? min(max(midiSequencer.currentTimeInBeats / totalBeats, 0.0), 1.0) : 0.0
                        let indicatorX = CGFloat(progress) * CGFloat(segment.lengthInBars * beatsPerBar) * beatWidth * zoomLevel

                        Rectangle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 2, height: trackHeight)
                            .offset(x: indicatorX)
                    }

                    if totalSteps > 0 {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                            .frame(width: selectionHighlightWidth, height: trackHeight - 8)
                            .offset(x: highlightOffsetX(), y: 4)
                            .animation(.easeInOut(duration: 0.12), value: selectedStep)
                    }

                                        ForEach(segment.items) { item in
                                            let cellWidth = stepWidth * CGFloat(item.duration ?? stepStride)
                                            MelodicLyricCellView(
                                                item: item,
                                                isSelected: item.position == selectedStep,
                                                cellWidth: cellWidth,
                                                unitWidth: stepWidth
                                            )
                                            .offset(x: CGFloat(item.position) * stepWidth)
                                            .contentShape(Rectangle())
                                            .onTapGesture(count: 2, coordinateSpace: .named("timeline")) { location in
                                                let rawStep = Int(location.x / stepWidth)
                                                let clamped = min(max(rawStep, 0), totalSteps > 0 ? totalSteps - 1 : 0)
                                                let snapped = snapStep(clamped)

                                                if let itemIndex = segment.items.firstIndex(where: {
                                                    let item = $0
                                                    let start = item.position
                                                    let end = start + (item.duration ?? stepStride)
                                                    return (start..<end).contains(snapped)
                                                }) {
                                                    let clickedItem = segment.items[itemIndex]
                                                    selectStep(clickedItem.position)
                                                    startWordEditing()
                                                }
                                            }
                                            .onTapGesture(count: 1, coordinateSpace: .named("timeline")) { location in
                                                handleBackgroundTap(at: location)
                                            }
                                        }
                    if let editingStep = editingWordStep {
                        let editorWidth = max(stepWidth * CGFloat(max(gridSizeInSteps, 1)) - 8, 100)
                        let editorHeight: CGFloat = 28
                        TextField("Lyric", text: $editingWord)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: editorWidth, height: editorHeight)
                            .focused($isInlineEditorFocused)
                            .onSubmit { commitWordEditing() }
                            .offset(
                                x: inlineEditorOffsetX(for: editingStep, width: editorWidth),
                                y: inlineEditorOffsetY(height: editorHeight)
                            )
                    }
                }
                .coordinateSpace(name: "timeline")
                .frame(width: CGFloat(segment.lengthInBars * beatsPerBar) * beatWidth * zoomLevel, height: trackHeight)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { location in handleBackgroundTap(at: location) }
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // 4. Status Bar
            HStack(spacing: 0) {
                Text(cellStatusDescription).padding(.horizontal)
                Spacer()
                Text(itemStatusDescription).padding(.horizontal)
                Spacer()
                Text("Items: \(segment.items.count)").padding(.horizontal)
            }
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onChange(of: currentTechnique, perform: techniqueSelectionChanged)
        .onChange(of: segment.lengthInBars) { _ in
            clampSelectedStep()
            melodicLyricPlayer.stop()
            persistSegment()
        }
        .onChange(of: gridSizeInSteps) { newValue in
            alignSelectionToGrid()
            segment.gridUnit = newValue
            persistSegment()
        }
        .onAppear {
            gridSizeInSteps = segment.gridUnit ?? 1 // Use saved or default
            registerKeyMonitor()
        }
        .onDisappear {
            melodicLyricPlayer.stop()
            stopPreview()
            unregisterKeyMonitor()
        }
        .onChange(of: isEditingName) { editing in
            if !editing { persistSegment() }
        }
    }

    // MARK: - Private Methods

    private func handleBackgroundTap(at location: CGPoint) {
        guard totalSteps > 0 else { return }
        let rawStep = Int(location.x / stepWidth)
        let clamped = min(max(rawStep, 0), totalSteps - 1)
        let snapped = snapStep(clamped)
        selectStep(snapped)
    }

    private func selectStep(_ step: Int) {
        let snapped = snapStep(step)
        selectedStep = snapped
        editingWordStep = nil
        isInlineEditorFocused = false

        let selectedItem = itemIndex(at: snapped).map { segment.items[$0] }
        let newTechnique = selectedItem?.technique ?? .normal
        if currentTechnique != newTechnique {
            isTechniqueUpdateInternal = true
            currentTechnique = newTechnique
        }
    }

    private func snapStep(_ step: Int) -> Int {
        guard totalSteps > 0 else { return 0 }
        let stride = stepStride
        guard stride > 0 else { return min(max(step, 0), totalSteps - 1) }
        let clamped = min(max(step, 0), totalSteps - 1)
        return (clamped / stride) * stride
    }

    private var stepStride: Int { max(gridSizeInSteps, 1) }

    private func itemIndex(at step: Int) -> Int? {
        segment.items.firstIndex { $0.position == step }
    }

    private func ensureItem(at step: Int, defaultPitch: Int? = nil, defaultOctave: Int = 0) -> (index: Int, isNew: Bool) {
        if let existing = itemIndex(at: step) {
            return (existing, false)
        }
        let pitchValue = defaultPitch ?? 0
        let techniqueValue = currentTechnique == .normal ? nil : currentTechnique
        let newItem = MelodicLyricItem(
            word: "",
            position: step,
            duration: stepStride, // Set default duration
            pitch: pitchValue,
            octave: defaultOctave,
            technique: techniqueValue
        )
        segment.items.append(newItem)
        segment.items.sort { $0.position < $1.position }
        let index = segment.items.firstIndex { $0.id == newItem.id } ?? segment.items.count - 1
        return (index, true)
    }

    private func midiNoteNumber(pitch: Int, octave: Int) -> Int? {
        guard pitch >= 1 && pitch <= 7 else { return nil }
        let scaleOffsets = [0, 2, 4, 5, 7, 9, 11] // Major scale intervals
        let baseC = 60 // Middle C
        let key = appData.preset?.key ?? "C"
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        let transpose = keyMap[key] ?? 0
        let midiValue = baseC + transpose + scaleOffsets[pitch - 1] + octave * 12
        guard midiValue >= 0 && midiValue <= 127 else { return nil }
        return midiValue
    }

    private func handlePitchInput(_ pitch: Int) {
        guard totalSteps > 0 else { return }

        // Special handling for rests (pitch 0)
        if pitch == 0 {
            let (index, _) = ensureItem(at: selectedStep)
            segment.items[index].pitch = 0
            segment.items[index].octave = 0
            segment.items[index].technique = nil
            stopPreview()
            persistSegment()
            moveSelection(by: stepStride)
            return
        }

        let octave: Int
        if let existingIndex = itemIndex(at: selectedStep) {
            // Item already exists, keep its octave when just changing the pitch.
            octave = segment.items[existingIndex].octave
        } else {
            // This is a new item, find the best octave based on the previous note.
            let previousItem = segment.items
                .filter { $0.position < selectedStep && $0.pitch != 0 }
                .max(by: { $0.position < $1.position })

            if let prev = previousItem, let prevMidi = midiNoteNumber(pitch: prev.pitch, octave: prev.octave) {
                var minDistance = Int.max
                var bestOctave = 0
                // Check a reasonable range of octaves to find the closest pitch
                for oct in -2...3 {
                    if let newMidi = midiNoteNumber(pitch: pitch, octave: oct) {
                        let distance = abs(newMidi - prevMidi)
                        if distance < minDistance {
                            minDistance = distance
                            bestOctave = oct
                        }
                    }
                }
                octave = bestOctave
            } else {
                // No previous note, use default octave.
                octave = 0
            }
        }

        // Get or create the item.
        // We pass the calculated octave to ensureItem, which will only use it for creation.
        let (index, _) = ensureItem(at: selectedStep, defaultPitch: pitch, defaultOctave: octave)
        
        // Update the item's properties.
        segment.items[index].pitch = pitch
        segment.items[index].octave = octave

        previewPitch(pitch: pitch, octave: octave)
        
        persistSegment()
        moveSelection(by: stepStride)
    }

    private func toggleTechnique(_ technique: PlayingTechnique) {
        guard let index = itemIndex(at: selectedStep) else { return }
        let currentValue = segment.items[index].technique
        let newValue: PlayingTechnique? = currentValue == technique ? nil : technique
        segment.items[index].technique = newValue
        isTechniqueUpdateInternal = true
        currentTechnique = newValue ?? .normal
        persistSegment()
    }

    private func startWordEditing() {
        guard totalSteps > 0 else { return }
        editingWordStep = selectedStep
        if let index = itemIndex(at: selectedStep) {
            editingWord = segment.items[index].word
        } else {
            editingWord = ""
        }
        isInlineEditorFocused = true
    }

    private func commitWordEditing() {
        guard let step = editingWordStep else { return }
        let (index, _) = ensureItem(at: step)
        segment.items[index].word = editingWord
        editingWordStep = nil
        isInlineEditorFocused = false
        moveSelection(by: stepStride)
        persistSegment()
    }

    private func cancelWordEditing() {
        editingWordStep = nil
        isInlineEditorFocused = false
    }

    private func moveSelection(by delta: Int) {
        guard totalSteps > 0 else {
            selectStep(0)
            return
        }
        let newValue = selectedStep + delta
        selectStep(newValue)
    }

    private func adjustPitch(direction: Int) {
        guard direction != 0 else { return }
        let (targetIndex, _) = ensureItem(at: selectedStep, defaultPitch: 1)
        if segment.items[targetIndex].pitch == 0 {
            // Promote rest to a default pitch before changing octave.
            segment.items[targetIndex].pitch = 1
        }
        var octave = segment.items[targetIndex].octave + direction
        octave = min(max(octave, -2), 2)
        segment.items[targetIndex].octave = octave
        previewPitch(pitch: segment.items[targetIndex].pitch, octave: octave)
        persistSegment()
    }

    private func removeItem(at step: Int) {
        segment.items.removeAll { $0.position == step }
        stopPreview()
        persistSegment()
    }

    private func techniqueSelectionChanged(_ technique: PlayingTechnique) {
        if isTechniqueUpdateInternal {
            isTechniqueUpdateInternal = false
            return
        }
        if let index = itemIndex(at: selectedStep) {
            segment.items[index].technique = technique == .normal ? nil : technique
            persistSegment()
        }
    }

    private func clampSelectedStep() {
        print("--- clampSelectedStep triggered ---")
        print("selectedStep before clamp: \(selectedStep)")
        selectedStep = snapStep(selectedStep)
    }

    private func alignSelectionToGrid() {
        print("--- alignSelectionToGrid triggered ---")
        print("selectedStep before align: \(selectedStep)")
        selectedStep = snapStep(selectedStep)
    }

    private var selectionHighlightWidth: CGFloat {
        max(stepWidth * CGFloat(stepStride) - 4, stepWidth * 0.6)
    }

    private func highlightOffsetX() -> CGFloat {
        let snapped = snapStep(selectedStep)
        let cellWidth = stepWidth * CGFloat(stepStride)
        let base = CGFloat(snapped) * stepWidth
        let inset = max((cellWidth - selectionHighlightWidth) / 2, 0)
        return base + inset
    }

    private func inlineEditorOffsetX(for step: Int, width: CGFloat) -> CGFloat {
        let snapped = snapStep(step)
        let cellWidth = stepWidth * CGFloat(stepStride)
        let base = CGFloat(snapped) * stepWidth
        let inset = max((cellWidth - width) / 2, 0)
        return base + inset
    }

    private func inlineEditorOffsetY(height: CGFloat) -> CGFloat {
        max((trackHeight - height) / 2, 4)
    }

    private var selectedItem: MelodicLyricItem? {
        itemIndex(at: selectedStep).map { segment.items[$0] }
    }


    private var cellStatusDescription: String {
        guard totalSteps > 0 else { return "No cells" }
        let stepsPerMeasure = beatsPerBar * stepsPerBeat
        let bar = selectedStep / stepsPerMeasure + 1
        let beat = (selectedStep % stepsPerMeasure) / stepsPerBeat + 1
        let subdivision = (selectedStep % stepsPerBeat) + 1

        return "Cell: Bar \(bar) Beat \(beat) Step \(subdivision)"
    }

    private var itemStatusDescription: String {
        guard let item = selectedItem else { return "Empty cell" }
        let wordDisplay = item.word.isEmpty ? "Word: -" : "Word: \(item.word)"
        let pitchDisplay = item.pitch == 0 ? "Rest" : "Pitch \(item.pitch) Oct \(item.octave)"
        let techniqueDisplay = item.technique?.chineseName ?? "普通"
        let durationDisplay = "Len: \(item.duration ?? stepStride)"
        return "\(wordDisplay) | \(pitchDisplay) | \(techniqueDisplay) | \(durationDisplay)"
    }

    private func applySustain() {
        guard selectedStep >= 0 else { return }

        // Find the note to modify: the last note starting at or before the selected step.
        // This handles both extending a previous note and shortening the current note.
        guard let itemToModify = segment.items.filter({ $0.position <= selectedStep }).max(by: { $0.position < $1.position }) else { return }

        // New duration extends to the end of the selected grid cell, ensuring it's a multiple of the grid size.
        let newDuration = selectedStep + stepStride - itemToModify.position
        guard newDuration >= 1 else { return }

        // Remove any items that are now covered by the sustained note.
        let coveredStartPosition = itemToModify.position + 1
        let coveredEndPosition = selectedStep + stepStride // End of range is exclusive
        segment.items.removeAll { $0.position >= coveredStartPosition && $0.position < coveredEndPosition }

        // Find the index again after removal, as it might have changed.
        guard let finalItemIndex = segment.items.firstIndex(where: { $0.id == itemToModify.id }) else { return }

        // Update the duration and persist.
        segment.items[finalItemIndex].duration = newDuration
        persistSegment()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Check if text field is currently focused - if so, don't handle custom keyboard events
        if let currentFirstResponder = NSApp.keyWindow?.firstResponder,
           currentFirstResponder is NSTextField || 
           currentFirstResponder is NSTextView {
            // Text field or text view is focused, allow normal text input processing
            return false
        }
        
        if editingWordStep != nil {
            switch event.keyCode {
            case 53: // Escape
                cancelWordEditing()
                return true
            case 36, 76: // Return or Enter
                commitWordEditing()
                return true
            default:
                return false
            }
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if characters.count == 1 && modifiers.isDisjoint(with: [.command, .option, .control]) {
            let char = characters.first!
            if let digit = char.wholeNumberValue, (0...7).contains(digit) {
                handlePitchInput(digit)
                return true
            }
            switch char {
            case "/":
                toggleTechnique(.slide)
                return true
            case "^":
                toggleTechnique(.bend)
                return true
            case "~":
                toggleTechnique(.vibrato)
                return true
            case "-":
                applySustain()
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 36, 76: // Return or Enter
            startWordEditing()
            return true
        case 123: // Left arrow
            moveSelection(by: -stepStride)
            return true
        case 124: // Right arrow
            moveSelection(by: stepStride)
            return true
        case 125: // Down arrow
            adjustPitch(direction: -1)
            return true
        case 126: // Up arrow
            adjustPitch(direction: 1)
            return true
        case 51: // Delete
            removeItem(at: selectedStep)
            return true
        default:
            break
        }

        return false
    }

    private func registerKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func unregisterKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func persistSegment() {
        appData.saveChanges()
    }

    private func toggleSegmentPlayback() {
        melodicLyricPlayer.play(segment: segment)
    }

    private func previewPitch(pitch: Int, octave: Int) {
        stopPreview()

        guard let midiValue = midiNoteNumber(pitch: pitch, octave: octave) else { return }
        let midiNote = UInt8(midiValue)

        let channel = UInt8(max(0, min(15, sanitizedEditorMidiChannel - 1)))
        midiManager.sendNoteOn(note: midiNote, velocity: 100, channel: channel)
        lastPreviewNote = midiNote
        let scheduledNote = midiNote
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard lastPreviewNote == scheduledNote else { return }
            midiManager.sendNoteOff(note: scheduledNote, velocity: 0, channel: channel)
            if lastPreviewNote == scheduledNote {
                lastPreviewNote = nil
            }
        }
    }

    private func stopPreview() {
        guard let note = lastPreviewNote else { return }
        let channel = UInt8(max(0, min(15, sanitizedEditorMidiChannel - 1)))
        midiManager.sendNoteOff(note: note, velocity: 0, channel: channel)
        lastPreviewNote = nil
    }


    private var sanitizedEditorMidiChannel: Int {
        min(max(editorMidiChannel, 1), 16)
    }
}

// MARK: - Subviews

struct MelodicLyricToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var gridSizeInSteps: Int
    @Binding var zoomLevel: CGFloat
    @Binding var segmentLengthInBars: Int
    @Binding var midiChannel: Int
    @State private var showingSettings = false
    @Binding var isPlayingSegment: Bool
    let onTogglePlayback: () -> Void
    // Corrected grid options: Label -> Number of 16th-note steps
    private let gridOptions: [(String, Int)] = [("1/4", 4), ("1/8", 2), ("1/16", 1)]

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onTogglePlayback) {
                Label(isPlayingSegment ? "Stop" : "Play", systemImage: isPlayingSegment ? "stop.circle.fill" : "play.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .help(isPlayingSegment ? "Stop segment preview" : "Play segment preview")

            Spacer()
            Picker("Technique", selection: $currentTechnique) {
                ForEach(PlayingTechnique.allCases) { Text($0.chineseName).tag($0) }
            }.frame(minWidth: 80).help("Playing Technique")
            Spacer()
            Picker("Grid", selection: $gridSizeInSteps) {
                ForEach(gridOptions, id: \.1) { Text($0.0).tag($0.1) }
            }.frame(minWidth: 80).help("Grid Snap")
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...4.0).frame(width: 100)
            }.help("Zoom Level")
            Spacer()
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
            }.buttonStyle(.bordered).popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                LyricSegmentSettingsView(lengthInBars: $segmentLengthInBars, midiChannel: $midiChannel)
            }
        }.pickerStyle(.menu)
    }
}

struct LyricSegmentSettingsView: View {
    @Binding var lengthInBars: Int
    @Binding var midiChannel: Int
    private let midiChannels = Array(1...16)
    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties").font(.headline)
            HStack {
                Text("Length (bars):")
                TextField("Length", value: $lengthInBars, format: .number).frame(width: 60)
            }
            HStack {
                Text("MIDI Channel:")
                Picker("MIDI Channel", selection: $midiChannel) {
                    ForEach(midiChannels, id: \.self) { channel in
                        Text("Channel \(channel)").tag(channel)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }
        }.padding()
    }
}

struct MelodicLyricGridBackground: View {
    let lengthInBars: Int, beatsPerBar: Int, beatWidth: CGFloat, trackHeight: CGFloat, zoomLevel: CGFloat, stepsPerBeat: Int, gridSizeInSteps: Int
    private var stepWidth: CGFloat { (beatWidth / CGFloat(stepsPerBeat)) * zoomLevel }

    var body: some View {
        Canvas { context, size in
            let totalSteps = lengthInBars * beatsPerBar * stepsPerBeat
            guard totalSteps > 0 else { return }

            let stepsPerBar = beatsPerBar * stepsPerBeat

            // Draw sub-beat lines (faint, dashed)
            let subBeatLineStyle = StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            var subBeatPath = Path()
            let lineStride = gridSizeInSteps
            if lineStride < stepsPerBeat {
                for step in stride(from: lineStride, through: totalSteps, by: lineStride) {
                    if step % stepsPerBeat != 0 {
                        let x = CGFloat(step) * stepWidth
                        subBeatPath.move(to: CGPoint(x: x, y: 0))
                        subBeatPath.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
            }
            context.stroke(subBeatPath, with: .color(.primary.opacity(0.15)), style: subBeatLineStyle)

            // Draw beat lines (less prominent)
            var beatPath = Path()
            for step in stride(from: stepsPerBeat, through: totalSteps, by: stepsPerBeat) {
                if step % stepsPerBar != 0 {
                    let x = CGFloat(step) * stepWidth
                    beatPath.move(to: CGPoint(x: x, y: 0))
                    beatPath.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(beatPath, with: .color(.primary.opacity(0.3)), lineWidth: 0.8)

            // Draw bar lines (most prominent)
            var barPath = Path()
            for step in stride(from: 0, through: totalSteps, by: stepsPerBar) {
                let x = CGFloat(step) * stepWidth
                barPath.move(to: CGPoint(x: x, y: 0))
                barPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(barPath, with: .color(Color(red: 0.5, green: 0.25, blue: 0.95).opacity(0.9)), lineWidth: 2.2)
        }
    }
}

struct MelodicLyricCellView: View {
    let item: MelodicLyricItem
    let isSelected: Bool
    let cellWidth: CGFloat
    let unitWidth: CGFloat

    // Dynamically calculate font sizes based on the cell's width
    private var pitchFontSize: CGFloat {
        return max(8, min(24, unitWidth * 0.6))
    }

    private var wordFontSize: CGFloat {
        return max(6, min(16, unitWidth * 0.4))
    }

    private var techniqueFontSize: CGFloat {
        return max(5, min(12, unitWidth * 0.3))
    }

    var body: some View {
        let baseColor = isSelected ? Color.accentColor : Color.gray
        let textColor = isSelected ? Color.white : Color.primary

        ZStack(alignment: .leading) {
            // The background shape with border
            RoundedRectangle(cornerRadius: 6)
                .fill(baseColor.opacity(isSelected ? 0.5 : 0.2))
                .stroke(baseColor, lineWidth: 1.5)

            // The text content
            VStack(alignment: .leading, spacing: 2) {
                OctaveDotsRow(count: max(item.octave, 0), color: textColor)
                HStack(spacing: 1) {
                    Text("\(item.pitch)")
                        .font(.system(size: pitchFontSize, weight: .bold, design: .monospaced))
                    if let technique = item.technique {
                        Text(technique.symbol)
                            .font(.system(size: techniqueFontSize))
                    }
                }
                .foregroundColor(textColor)
                OctaveDotsRow(count: max(-item.octave, 0), color: textColor)
                Text(item.word)
                    .font(.system(size: wordFontSize, weight: .regular))
                    .foregroundColor(textColor)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading) // Let the ZStack control the width
        }
        .frame(width: cellWidth - 2)
        .shadow(radius: isSelected ? 3 : 1, y: 1)
    }
}

struct OctaveDotsRow: View {
    let count: Int
    let color: Color

    var body: some View {
        Group {
            if count > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { _ in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Preview Provider

struct MelodicLyricEditorView_Previews: PreviewProvider {
    @State static var mockSegment: MelodicLyricSegment = {
        var segment = MelodicLyricSegment(name: "Test Verse", lengthInBars: 2)
        segment.items = [
            MelodicLyricItem(word: "你", position: 0, pitch: 5, octave: 0),
            MelodicLyricItem(word: "好", position: 2, pitch: 6, octave: 0),
            MelodicLyricItem(word: "世", position: 4, pitch: 1, octave: 1, technique: .vibrato),
            MelodicLyricItem(word: "界", position: 6, pitch: 7, octave: 0)
        ]
        return segment
    }()

    static var previews: some View {
        let midiManager = MidiManager()
        let appData = AppData(midiManager: midiManager)
        appData.preset?.melodicLyricSegments = [mockSegment]
        return MelodicLyricEditorView(segment: $mockSegment)
            .environmentObject(midiManager)
            .environmentObject(appData)
            .frame(width: 800, height: 400)
    }
}
