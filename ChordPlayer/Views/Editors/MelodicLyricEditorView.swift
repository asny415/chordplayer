
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
    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedTick: Int = 0
    @State private var editingWordAtTick: Int? = nil
    @State private var editingWord: String = ""
    @State private var isTechniqueUpdateInternal = false
    @State private var keyMonitor: Any?
    @State private var lastPreviewNote: UInt8? = nil
    
    
    // In-place name editing state
    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isInlineEditorFocused: Bool

    // Layout constants
    private let beatWidth: CGFloat = 120
    private var beatsPerBar: Int { appData.preset?.timeSignature.beatsPerMeasure ?? 4 } // Use time signature from AppData
    private let ticksPerBeat: Int = 12 // The core of the new timing system
    private var totalTicks: Int { segment.lengthInBars * beatsPerBar * ticksPerBeat }
    private var tickWidth: CGFloat { (beatWidth / CGFloat(ticksPerBeat)) * zoomLevel }
    private let trackHeight: CGFloat = 120

    init(segment: Binding<MelodicLyricSegment>) {
        self._segment = segment
        self._selectedTick = State(initialValue: 0)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 4) {
                titleView
                toolbar
                editorContent
                statusBar
            }
            .onChange(of: selectedTick) { _,newTick in
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newTick, anchor: .center)
                    }
                }
            }
            .onChange(of: currentTechnique) { _, newTechnique in
                techniqueSelectionChanged(newTechnique)
            }
            .onChange(of: segment.lengthInBars) {
                clampSelectedTick()
                melodicLyricPlayer.stop()
                persistSegment()
            }
            .onChange(of: segment.activeResolution) { _,newValue in
                alignSelectionToGrid()
                persistSegment()
            }
            .onAppear {
                registerKeyMonitor()
            }
            .onDisappear {
                melodicLyricPlayer.stop()
                stopPreview()
                unregisterKeyMonitor()
            }
            .onChange(of: isEditingName) { _, editing in
                if !editing { persistSegment() }
            }
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var titleView: some View {
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
    }

    @ViewBuilder
    private var toolbar: some View {
        MelodicLyricToolbar(
            currentTechnique: $currentTechnique,
            resolution: $segment.activeResolution,
            zoomLevel: $zoomLevel,
            segmentLengthInBars: $segment.lengthInBars,
            midiChannel: $appData.lyricsEditorMidiChannel,
            isPlayingSegment: $melodicLyricPlayer.isPlaying,
            segmentKey: $segment.key,
            presetKey: appData.preset?.key ?? "C",
            onTogglePlayback: toggleSegmentPlayback
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial) // Use material background
    }

    @ViewBuilder
    private var editorContent: some View {
        ScrollView([.horizontal]) {
            ZStack(alignment: .topLeading) {
                // Layer 1: Background Grid
                MelodicLyricGridBackground(
                    lengthInBars: segment.lengthInBars, beatsPerBar: beatsPerBar, beatWidth: beatWidth,
                    trackHeight: trackHeight, zoomLevel: zoomLevel, ticksPerBeat: ticksPerBeat,
                    resolution: segment.activeResolution
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

                if totalTicks > 0 {
                    // Add a static grid of invisible anchor views for the ScrollViewReader to target.
                    HStack(spacing: 0) {
                        ForEach(0..<totalTicks, id: \.self) { tick in
                            Color.clear
                                .frame(width: tickWidth, height: 1)
                                .id(tick)
                        }
                    }
                    .frame(height: 1)

                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        .frame(width: selectionHighlightWidth, height: trackHeight - 8)
                        .offset(x: highlightOffsetX(), y: 4)
                        .animation(.easeInOut(duration: 0.12), value: selectedTick)
                }

                ForEach(segment.items) { item in
                    let cellWidth = tickWidth * CGFloat(item.durationInTicks ?? tickStride)
                    MelodicLyricCellView(
                        item: item,
                        isSelected: item.positionInTicks == selectedTick,
                        cellWidth: cellWidth,
                        unitWidth: tickWidth * 3 // Restore font size to be based on 16th note width
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        selectTick(item.positionInTicks)
                        startWordEditing()
                    }
                    .onTapGesture(count: 1) {
                        selectTickAndOptimizeGrid(at: item.positionInTicks)
                    }
                    .offset(x: CGFloat(item.positionInTicks) * tickWidth)
                }
                if let editingTick = editingWordAtTick {
                    let editorWidth = max(tickWidth * CGFloat(max(tickStride, 1)) - 8, 100)
                    let editorHeight: CGFloat = 28
                    TextField("Lyric", text: $editingWord)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: editorWidth, height: editorHeight)
                        .focused($isInlineEditorFocused)
                        .onSubmit { commitAndAdvance() }
                        .offset(
                            x: inlineEditorOffsetX(for: editingTick, width: editorWidth),
                            y: inlineEditorOffsetY(height: editorHeight)
                        )
                }
            }
            .frame(width: CGFloat(segment.lengthInBars * beatsPerBar) * beatWidth * zoomLevel, height: trackHeight)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { location in handleBackgroundTap(at: location) }
        }
        .background(.ultraThickMaterial) // Use thick material
        .clipShape(RoundedRectangle(cornerRadius: 8)) // Add rounded corners
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1) // Add a subtle border
        )
        .padding(.horizontal) // Add horizontal padding to the editor
    }

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 12) { // Add spacing
            Text(cellStatusDescription)
            Spacer()
            Text(itemStatusDescription)
            Spacer()
            Text("Items: \(segment.items.count)")
        }
        .font(.caption) // Use smaller font for status
        .foregroundColor(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.regularMaterial) // Use material background
    }

    // MARK: - Private Methods

    private func selectTickAndOptimizeGrid(at tick: Int) {
        // 1. Find if the click landed within an existing item.
        let itemAtTick = segment.items.first { item in
            tick >= item.positionInTicks && tick < (item.positionInTicks + (item.durationInTicks ?? tickStride))
        }

        // 2. Determine the base position and duration for our calculation.
        // If we found an item, use its properties. Otherwise, snap the clicked tick and use the current stride.
        let positionForGridCalc = itemAtTick?.positionInTicks ?? snapTick(tick)
        let durationForGridCalc = itemAtTick?.durationInTicks ?? tickStride

        // 3. Find the optimal grid using the position-first, optimized logic.
        let sortedResolutions = GridResolution.allCases.sorted { $0.stepsPerBeat < $1.stepsPerBeat }
        for resolution in sortedResolutions {
            let newTickStride = ticksPerBeat / resolution.stepsPerBeat
            guard newTickStride > 0 else { continue }

            let positionIsCompatible = (positionForGridCalc % newTickStride == 0)
            let durationIsCompatible = (durationForGridCalc % newTickStride == 0)

            if positionIsCompatible && durationIsCompatible {
                // This is the best-fit grid. Apply it and stop searching.
                segment.activeResolution = resolution
                break
            }
        }

        // 4. Finally, select the definitive tick. This will be snapped to the new grid.
        selectTick(positionForGridCalc)
    }

    private func handleBackgroundTap(at location: CGPoint) {
        guard totalTicks > 0 else { return }
        let rawTick = Int(location.x / tickWidth)
        let clamped = min(max(rawTick, 0), totalTicks - 1)
        // Call the new centralized logic.
        selectTickAndOptimizeGrid(at: clamped)
    }

    private func selectTick(_ tick: Int) {
        let snapped = snapTick(tick)
        selectedTick = snapped
        editingWordAtTick = nil
        isInlineEditorFocused = false

        let selectedItem = itemIndex(at: snapped).map { segment.items[$0] }
        let newTechnique = selectedItem?.technique ?? .normal
        if currentTechnique != newTechnique {
            isTechniqueUpdateInternal = true
            currentTechnique = newTechnique
        }
    }

    private func snapTick(_ tick: Int) -> Int {
        guard totalTicks > 0 else { return 0 }
        let stride = tickStride
        guard stride > 0 else { return min(max(tick, 0), totalTicks - 1) }
        let clamped = min(max(tick, 0), totalTicks - 1)
        return (clamped / stride) * stride
    }

    private var tickStride: Int { 
        let stepsPerBeat = segment.activeResolution.stepsPerBeat
        guard stepsPerBeat > 0 else { return 1 }
        return ticksPerBeat / stepsPerBeat
    }

    private func itemIndex(at tick: Int) -> Int? {
        segment.items.firstIndex { $0.positionInTicks == tick }
    }

    private func ensureItem(at tick: Int, defaultPitch: Int? = nil, defaultOctave: Int = 0) -> (index: Int, isNew: Bool) {
        if let existing = itemIndex(at: tick) {
            return (existing, false)
        }
        let pitchValue = defaultPitch ?? 0
        let techniqueValue = currentTechnique == .normal ? nil : currentTechnique
        let newItem = MelodicLyricItem(
            word: "",
            positionInTicks: tick,
            durationInTicks: tickStride, // Set default duration in ticks
            pitch: pitchValue,
            octave: defaultOctave,
            technique: techniqueValue
        )
        segment.items.append(newItem)
        segment.items.sort { $0.positionInTicks < $1.positionInTicks }
        let index = segment.items.firstIndex { $0.id == newItem.id } ?? segment.items.count - 1
        return (index, true)
    }

    private func midiNoteNumber(pitch: Int, octave: Int, offset: Int? = nil) -> Int? {
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
        let midiValue = baseC + transpose + scaleOffsets[pitch - 1] + octave * 12 + (offset ?? 0)
        guard midiValue >= 0 && midiValue <= 127 else { return nil }
        return midiValue
    }

    private func handlePitchInput(_ pitch: Int) {
        guard totalTicks > 0 else { return }

        // Special handling for rests (pitch 0)
        if pitch == 0 {
            let (index, _) = ensureItem(at: selectedTick)
            segment.items[index].pitch = 0
            segment.items[index].octave = 0
            segment.items[index].technique = nil
            stopPreview()
            persistSegment()
            moveSelection(by: tickStride)
            return
        }

        let octave: Int
        if let existingIndex = itemIndex(at: selectedTick) {
            // Item already exists, keep its octave when just changing the pitch.
            octave = segment.items[existingIndex].octave
        } else {
            // This is a new item, find the best octave based on the previous note.
            let previousItem = segment.items
                .filter { $0.positionInTicks < selectedTick && $0.pitch != 0 }
                .max(by: { $0.positionInTicks < $1.positionInTicks })

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
        let (index, _) = ensureItem(at: selectedTick, defaultPitch: pitch, defaultOctave: octave)
        
        // Update the item's properties.
        segment.items[index].pitch = pitch
        segment.items[index].octave = octave

        previewPitch(pitch: pitch, octave: octave)
        
        persistSegment()
        moveSelection(by: tickStride)
    }

    private func toggleTechnique(_ technique: PlayingTechnique) {
        guard let index = itemIndex(at: selectedTick) else { return }
        let currentValue = segment.items[index].technique
        let newValue: PlayingTechnique? = currentValue == technique ? nil : technique
        segment.items[index].technique = newValue
        isTechniqueUpdateInternal = true
        currentTechnique = newValue ?? .normal
        persistSegment()
    }

    private func startWordEditing(withInitialCharacter initialChar: String? = nil) {
        guard totalTicks > 0 else { return }
        editingWordAtTick = selectedTick
        
        if let initialChar = initialChar {
            editingWord = initialChar
        } else if let index = itemIndex(at: selectedTick) {
            editingWord = segment.items[index].word
        } else {
            editingWord = ""
        }
        
        isInlineEditorFocused = true
    }

    private func commitAndAdvance() {
        guard let tick = editingWordAtTick else { return }

        // 1. Commit the current word
        let (index, _) = ensureItem(at: tick)
        segment.items[index].word = editingWord
        
        // We are about to move, so clear current editing state
        editingWordAtTick = nil
        isInlineEditorFocused = false

        // 2. Find the next item to jump to
        let nextItem = segment.items
            .filter { $0.positionInTicks > tick }
            .min(by: { $0.positionInTicks < $1.positionInTicks })

        if let nextItem = nextItem {
            // 3. Position-first grid optimization
            // Sort resolutions from coarsest (fewest steps) to finest (most steps)
            let sortedResolutions = GridResolution.allCases.sorted { $0.stepsPerBeat < $1.stepsPerBeat }

            // Find the best grid that fits both position and duration
            for resolution in sortedResolutions {
                let tickStride = ticksPerBeat / resolution.stepsPerBeat
                
                // Ensure stride is valid and duration exists
                guard tickStride > 0, let duration = nextItem.durationInTicks else { continue }

                // Condition A: Position is compatible
                let positionIsCompatible = (nextItem.positionInTicks % tickStride == 0)
                // Condition B: Duration is compatible
                let durationIsCompatible = (duration % tickStride == 0)

                if positionIsCompatible && durationIsCompatible {
                    // This is the best-fit grid. Apply it and stop searching.
                    segment.activeResolution = resolution
                    break 
                }
            }

            // 4. Finally, select the tick.
            selectTick(nextItem.positionInTicks)

        } else {
            // If no next item, just move by one grid step
            moveSelection(by: tickStride)
        }
        
        persistSegment()
    }

    private func cancelWordEditing() {
        editingWordAtTick = nil
        isInlineEditorFocused = false
    }

    private func moveSelection(by delta: Int) {
        guard totalTicks > 0 else {
            selectTick(0)
            return
        }
        let newValue = selectedTick + delta
        selectTick(newValue)
    }

    private func adjustPitch(direction: Int) {
        guard direction != 0 else { return }
        let (targetIndex, _) = ensureItem(at: selectedTick, defaultPitch: 1)
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

    private func togglePitchOffset(_ offset: Int) {
        guard let index = itemIndex(at: selectedTick) else { return }
        
        // 如果当前偏移量与目标一致，则取消偏移 (设为 nil)
        // 否则，设置新的偏移量
        if segment.items[index].pitchOffset == offset {
            segment.items[index].pitchOffset = nil
        } else {
            segment.items[index].pitchOffset = offset
        }
        
        // 预览并保存
        previewPitch(pitch: segment.items[index].pitch,
                     octave: segment.items[index].octave,
                     offset: segment.items[index].pitchOffset)
        persistSegment()
    }

    private func removeItem(at tick: Int) {
        segment.items.removeAll { $0.positionInTicks == tick }
        stopPreview()
        persistSegment()
    }

    private func techniqueSelectionChanged(_ technique: PlayingTechnique) {
        if isTechniqueUpdateInternal {
            isTechniqueUpdateInternal = false
            return
        }
        if let index = itemIndex(at: selectedTick) {
            segment.items[index].technique = technique == .normal ? nil : technique
            persistSegment()
        }
    }

    private func clampSelectedTick() {
        selectedTick = snapTick(selectedTick)
    }

    private func alignSelectionToGrid() {
        selectedTick = snapTick(selectedTick)
    }

    private var selectionHighlightWidth: CGFloat {
        max(tickWidth * CGFloat(tickStride) - 4, tickWidth * 0.6)
    }

    private func highlightOffsetX() -> CGFloat {
        let snapped = snapTick(selectedTick)
        let cellWidth = tickWidth * CGFloat(tickStride)
        let base = CGFloat(snapped) * tickWidth
        let inset = max((cellWidth - selectionHighlightWidth) / 2, 0)
        return base + inset
    }

    private func inlineEditorOffsetX(for tick: Int, width: CGFloat) -> CGFloat {
        let snapped = snapTick(tick)
        let cellWidth = tickWidth * CGFloat(tickStride)
        let base = CGFloat(snapped) * tickWidth
        let inset = max((cellWidth - width) / 2, 0)
        return base + inset
    }

    private func inlineEditorOffsetY(height: CGFloat) -> CGFloat {
        max((trackHeight - height) / 2, 4)
    }

    private var selectedItem: MelodicLyricItem? {
        itemIndex(at: selectedTick).map { segment.items[$0] }
    }


    private var cellStatusDescription: String {
        guard totalTicks > 0 else { return "No cells" }
        let ticksPerMeasure = beatsPerBar * ticksPerBeat
        let bar = selectedTick / ticksPerMeasure + 1
        let beat = (selectedTick % ticksPerMeasure) / ticksPerBeat + 1
        let tickInBeat = (selectedTick % ticksPerBeat)

        return "Bar \(bar) Beat \(beat) Tick \(tickInBeat)"
    }

    private var itemStatusDescription: String {
        guard let item = selectedItem else { return "Empty cell" }
        let wordDisplay = item.word.isEmpty ? "Word: -" : "Word: \(item.word)"
        let pitchDisplay = item.pitch == 0 ? "Rest" : "Pitch \(item.pitch) Oct \(item.octave)"
        let techniqueDisplay = item.technique?.chineseName ?? "普通"
        let durationDisplay = "Len: \(item.durationInTicks ?? tickStride) ticks"
        return "\(wordDisplay) | \(pitchDisplay) | \(techniqueDisplay) | \(durationDisplay)"
    }

    private func applySustain() {
        guard selectedTick >= 0 else { return }

        // Find the note to modify: the last note starting at or before the selected tick.
        guard let itemToModify = segment.items.filter({ $0.positionInTicks <= selectedTick }).max(by: { $0.positionInTicks < $1.positionInTicks }) else { return }

        // New duration extends to the end of the selected grid cell.
        let newDurationInTicks = selectedTick + tickStride - itemToModify.positionInTicks
        guard newDurationInTicks >= 1 else { return }

        // Remove any items that are now covered by the sustained note.
        let coveredStartTick = itemToModify.positionInTicks + 1
        let coveredEndTick = selectedTick + tickStride // End of range is exclusive
        segment.items.removeAll { $0.positionInTicks >= coveredStartTick && $0.positionInTicks < coveredEndTick }

        // Find the index again after removal, as it might have changed.
        guard let finalItemIndex = segment.items.firstIndex(where: { $0.id == itemToModify.id }) else { return }

        // Update the duration and persist.
        segment.items[finalItemIndex].durationInTicks = newDurationInTicks
        persistSegment()
        
        // UX Improvement: Move to the next cell after applying sustain.
        moveSelection(by: tickStride)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Check if text field is currently focused - if so, don't handle custom keyboard events
        if let currentFirstResponder = NSApp.keyWindow?.firstResponder,
           currentFirstResponder is NSTextField || 
           currentFirstResponder is NSTextView {
            // Text field or text view is focused, allow normal text input processing
            return false
        }
        
        if editingWordAtTick != nil {
            switch event.keyCode {
            case 53: // Escape
                cancelWordEditing()
                return true
            case 36, 76: // Return or Enter
                commitAndAdvance()
                return true
            default:
                return false
            }
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers ?? ""

        if characters.count == 1 && modifiers.isDisjoint(with: [.command, .option, .control]) {
            let char = characters.first!
            
            // Rule 1: Handle specific commands first.
            if let digit = char.wholeNumberValue, (0...7).contains(digit) {
                handlePitchInput(digit)
                return true
            }
            switch char {
            case "/", "^", "~", "-":
                // This is a command, handle it and stop.
                switch char {
                    case "/": toggleTechnique(.slide)
                    case "^": toggleTechnique(.bend)
                    case "~": toggleTechnique(.vibrato)
                    case "-": applySustain()
                    default: break
                }
                return true
            case "#":
                togglePitchOffset(1) // 升半音
                return true
            case "b":
                togglePitchOffset(-1) // 降半音
                return true
            default:
                // Rule 2: Check if it's a character suitable for starting a lyric.
                // This prevents control characters from arrow keys from being captured.
                if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol {
                    // Rule 3: To support IME, start editing with an EMPTY text field.
                    startWordEditing() // Call without initial character.
                    return false // Return false to forward the event to the new text field.
                }
            }
        }

        switch event.keyCode {
        case 36, 76: // Return or Enter
            startWordEditing()
            return true
        case 123: // Left arrow
            moveSelection(by: -tickStride)
            return true
        case 124: // Right arrow
            moveSelection(by: tickStride)
            return true
        case 125: // Down arrow
            adjustPitch(direction: -1)
            return true
        case 126: // Up arrow
            adjustPitch(direction: 1)
            return true
        case 51: // Delete
            removeItem(at: selectedTick)
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
        let channel = UInt8(max(0, min(15, sanitizedEditorMidiChannel - 1)))
        melodicLyricPlayer.play(segment: segment, midiChannel: channel)
    }

    private func previewPitch(pitch: Int, octave: Int, offset: Int? = nil) {
        stopPreview()

        guard let midiValue = midiNoteNumber(pitch: pitch, octave: octave, offset: offset) else { return }
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
        min(max(appData.lyricsEditorMidiChannel, 1), 16)
    }
}

// MARK: - Subviews

struct MelodicLyricToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var resolution: GridResolution
    @Binding var zoomLevel: CGFloat
    @Binding var segmentLengthInBars: Int
    @Binding var midiChannel: Int
    @State private var showingSettings = false
    @Binding var isPlayingSegment: Bool
    @Binding var segmentKey: String?
    let presetKey: String
    let onTogglePlayback: () -> Void

    private let allKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    var body: some View {
        HStack(spacing: 16) {
            // Group 1: Playback
            Button(action: onTogglePlayback) {
                Label(isPlayingSegment ? "Stop" : "Play", systemImage: isPlayingSegment ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .tint(isPlayingSegment ? .red : .accentColor)
            .help(isPlayingSegment ? "Stop segment preview" : "Play segment preview")

            // Group 2: Editing Tools
            Picker("Technique", selection: $currentTechnique) {
                ForEach(PlayingTechnique.allCases) { Text($0.chineseName).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 80)
            .help("Playing Technique")

            Picker("Grid", selection: $resolution) {
                ForEach(GridResolution.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120)
            .help("Grid Snap")
            
            keySelectionMenu // Add the key selection menu here

            Spacer()

            // Group 3: View Controls
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...4.0)
                    .frame(width: 100)
            }
            .foregroundColor(.secondary)
            .help("Zoom Level")

            // Group 4: Settings
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                LyricSegmentSettingsView(lengthInBars: $segmentLengthInBars, midiChannel: $midiChannel)
            }
        }
        .labelStyle(.iconOnly)
    }
    
    @ViewBuilder
    private var keySelectionMenu: some View {
        Menu {
            ForEach(allKeys, id: \.self) { key in
                Button(action: { segmentKey = key }) {
                    Text(key)
                }
            }
            if segmentKey != nil {
                Divider()
                Button(role: .destructive, action: { segmentKey = nil }) {
                    Text("Reset to Preset Key")
                }
            }
        } label: {
            Text("Key: \(segmentKey ?? presetKey)")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(5)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

struct LyricSegmentSettingsView: View {
    @Binding var lengthInBars: Int
    @Binding var midiChannel: Int
    private let midiChannels = Array(1...16)
    var body: some View {
        VStack(spacing: 16) {
            Text("Segment Properties").font(.title3).fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Length (bars):")
                    Spacer()
                    TextField("Length", value: $lengthInBars, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                HStack {
                    Text("MIDI Channel:")
                    Spacer()
                    Picker("MIDI Channel", selection: $midiChannel) {
                        ForEach(midiChannels, id: \.self) { channel in
                            Text("Channel \(channel)").tag(channel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }
}

struct MelodicLyricGridBackground: View {
    let lengthInBars: Int, beatsPerBar: Int, beatWidth: CGFloat, trackHeight: CGFloat, zoomLevel: CGFloat, ticksPerBeat: Int, resolution: GridResolution
    private var tickWidth: CGFloat { (beatWidth / CGFloat(ticksPerBeat)) * zoomLevel }

    var body: some View {
        Canvas { context, size in
            let totalTicks = lengthInBars * beatsPerBar * ticksPerBeat
            guard totalTicks > 0 else { return }

            let ticksPerBar = beatsPerBar * ticksPerBeat
            
            // The number of ticks for each grid line, based on the current resolution.
            let tickStride = ticksPerBeat / resolution.stepsPerBeat

            // Draw sub-beat lines (faint, dashed) for the selected grid resolution
            let subBeatLineStyle = StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            var subBeatPath = Path()
            if tickStride > 0 {
                for tick in stride(from: 0, through: totalTicks, by: tickStride) {
                    // Don't draw over the stronger beat lines
                    if tick % ticksPerBeat != 0 {
                        let x = CGFloat(tick) * tickWidth
                        subBeatPath.move(to: CGPoint(x: x, y: 0))
                        subBeatPath.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
            }
            context.stroke(subBeatPath, with: .color(.primary.opacity(0.15)), style: subBeatLineStyle)

            // Draw beat lines (less prominent)
            var beatPath = Path()
            for tick in stride(from: 0, through: totalTicks, by: ticksPerBeat) {
                // Don't draw over the stronger bar lines
                if tick % ticksPerBar != 0 {
                    let x = CGFloat(tick) * tickWidth
                    beatPath.move(to: CGPoint(x: x, y: 0))
                    beatPath.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(beatPath, with: .color(.primary.opacity(0.3)), lineWidth: 0.8)

            // Draw bar lines (most prominent)
            var barPath = Path()
            for tick in stride(from: 0, through: totalTicks, by: ticksPerBar) {
                let x = CGFloat(tick) * tickWidth
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
                    
                    if let offset = item.pitchOffset {
                        if offset > 0 {
                            Text("#")
                                .font(.system(size: pitchFontSize * 0.8, weight: .bold))
                                .baselineOffset(pitchFontSize * 0.2)
                        } else if offset < 0 {
                            // 使用小写 "b" 作为降号
                            Text("b")
                                .font(.system(size: pitchFontSize, weight: .bold))
                        }
                    }

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
        var segment = MelodicLyricSegment(name: "Test Verse", lengthInBars: 2, resolution: .sixteenth)
        segment.items = [
            MelodicLyricItem(word: "你", positionInTicks: 0, durationInTicks: 6, pitch: 5, octave: 0),
            MelodicLyricItem(word: "好", positionInTicks: 6, durationInTicks: 6, pitch: 6, octave: 0),
            MelodicLyricItem(word: "世", positionInTicks: 12, durationInTicks: 6, pitch: 1, octave: 1, technique: .vibrato),
            MelodicLyricItem(word: "界", positionInTicks: 18, durationInTicks: 6, pitch: 7, octave: 0)
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
            .frame(width: 1000, height: 400)
    }
}
