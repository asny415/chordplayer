
import SwiftUI
import AppKit

// MARK: - Main Editor View

struct MelodicLyricEditorView: View {
    @EnvironmentObject private var appData: AppData
    @EnvironmentObject private var midiManager: MidiManager
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
    @State private var lastPreviewNote: UInt8?
    @State private var isPlayingSegment = false
    @State private var scheduledPlaybackNotes: [ScheduledPlaybackNote] = []
    @State private var playbackCompletionTask: DispatchWorkItem?
    @State private var playbackProgress: Double = 0.0
    @State private var playbackProgressTasks: [DispatchWorkItem] = []

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
                isPlayingSegment: isPlayingSegment,
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

                    if isPlayingSegment {
                        let indicatorX = playbackIndicatorOffsetX()
                        Rectangle()
                            .fill(Color.red.opacity(0.8))
                            .frame(width: 2, height: trackHeight)
                            .offset(x: indicatorX)
                            .animation(.linear(duration: 0.05), value: playbackProgress)
                    }

                    if totalSteps > 0 {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                            .frame(width: selectionHighlightWidth, height: trackHeight - 8)
                            .offset(x: highlightOffsetX(), y: 4)
                            .animation(.easeInOut(duration: 0.12), value: selectedStep)
                    }

                    ForEach(segment.items) { item in
                        MelodicLyricCellView(
                            item: item,
                            isSelected: item.position == selectedStep,
                            stepWidth: stepWidth
                        )
                        .offset(x: CGFloat(item.position) * stepWidth)
                        .onTapGesture {
                            selectStep(item.position)
                        }
                        .onTapGesture(count: 2) {
                            selectStep(item.position)
                            startWordEditing()
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
            stopSegmentPlayback()
            persistSegment()
        }
        .onChange(of: gridSizeInSteps) { _ in alignSelectionToGrid() }
        .onAppear { registerKeyMonitor() }
        .onDisappear {
            stopSegmentPlayback()
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
            pitch: pitchValue,
            octave: defaultOctave,
            technique: techniqueValue
        )
        segment.items.append(newItem)
        segment.items.sort { $0.position < $1.position }
        let index = segment.items.firstIndex { $0.id == newItem.id } ?? segment.items.count - 1
        return (index, true)
    }

    private func handlePitchInput(_ pitch: Int) {
        guard totalSteps > 0 else { return }
        let (index, _) = ensureItem(at: selectedStep, defaultPitch: pitch)
        segment.items[index].pitch = pitch
        if pitch == 0 {
            segment.items[index].octave = 0
            segment.items[index].technique = nil
            stopPreview()
        } else {
            previewPitch(pitch: pitch, octave: segment.items[index].octave)
        }
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
            selectedStep = 0
            return
        }
        let newValue = selectedStep + delta
        selectedStep = snapStep(newValue)
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
        selectedStep = snapStep(selectedStep)
    }

    private func alignSelectionToGrid() {
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

    private func playbackIndicatorOffsetX() -> CGFloat {
        let totalWidth = CGFloat(segment.lengthInBars * beatsPerBar) * beatWidth * zoomLevel
        return CGFloat(playbackProgress) * totalWidth
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
        return "\(wordDisplay) | \(pitchDisplay) | \(techniqueDisplay)"
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
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
        // Allow default behaviour when the title field is being edited to preserve standard text editing keys.
        if isEditingName {
            return false
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
            return false
        }

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
        if isPlayingSegment {
            stopSegmentPlayback()
        } else {
            startSegmentPlayback()
        }
    }

    private func startSegmentPlayback() {
        guard let preset = appData.preset else { return }
        stopSegmentPlayback()
        stopPreview()

        let bpm = preset.bpm
        guard bpm > 0 else { return }

        // --- Begin Technique-Aware Playback Logic ---

        enum MusicalAction {
            case playNote(item: MelodicLyricItem, offTimeMs: Double)
            case slide(from: MelodicLyricItem, to: MelodicLyricItem, offTimeMs: Double)
            case vibrato(item: MelodicLyricItem, offTimeMs: Double)
            case bend(item: MelodicLyricItem, offTimeMs: Double)
        }

        let msPerBeat = 60_000.0 / bpm
        let msPerStep = msPerBeat / Double(stepsPerBeat)
        let totalStepsInSegment = self.totalSteps

        let itemsSortedByTime = segment.items.sorted { $0.position < $1.position }
        var consumedItemIDs = Set<UUID>()
        var actions: [MusicalAction] = []

        // 1. Build MusicalAction list
        for i in 0..<itemsSortedByTime.count {
            let currentItem = itemsSortedByTime[i]
            if consumedItemIDs.contains(currentItem.id) || currentItem.pitch == 0 { continue }

            let nextItemPosition = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 })?.position ?? totalStepsInSegment
            let noteOffTimeMs = Double(nextItemPosition) * msPerStep

            switch currentItem.technique {
            case .slide:
                if let slideTargetItem = itemsSortedByTime.dropFirst(i + 1).first(where: { $0.pitch > 0 }) {
                    consumedItemIDs.insert(slideTargetItem.id)
                    let slideTargetNextPos = itemsSortedByTime.firstIndex(of: slideTargetItem).flatMap { itemsSortedByTime.dropFirst($0 + 1).first(where: { $0.pitch > 0 })?.position } ?? totalStepsInSegment
                    let slideOffTimeMs = Double(slideTargetNextPos) * msPerStep
                    actions.append(.slide(from: currentItem, to: slideTargetItem, offTimeMs: slideOffTimeMs))
                } else {
                    actions.append(.playNote(item: currentItem, offTimeMs: noteOffTimeMs))
                }
            case .vibrato:
                actions.append(.vibrato(item: currentItem, offTimeMs: noteOffTimeMs))
            case .bend:
                actions.append(.bend(item: currentItem, offTimeMs: noteOffTimeMs))
            default:
                actions.append(.playNote(item: currentItem, offTimeMs: noteOffTimeMs))
            }
        }

        guard !actions.isEmpty else { return }

        // 2. Schedule MIDI events from actions
        let channel = UInt8(max(0, min(15, appData.chordMidiChannel - 1)))
        let startTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0 + 80.0
        var scheduled: [ScheduledPlaybackNote] = []

        for action in actions {
            var onId: UUID? = nil
            var offId: UUID? = nil
            var note: UInt8 = 0

            switch action {
            case .playNote(let item, let offTimeMs):
                guard let midiNote = midiNoteNumber(for: item.pitch, octave: item.octave) else { continue }
                note = midiNote
                let noteOnTime = startTimeMs + Double(item.position) * msPerStep
                let noteOffTime = startTimeMs + offTimeMs * 0.98
                if noteOffTime > noteOnTime {
                    onId = midiManager.scheduleNoteOn(note: midiNote, velocity: 100, channel: channel, scheduledUptimeMs: noteOnTime)
                    offId = midiManager.scheduleNoteOff(note: midiNote, velocity: 0, channel: channel, scheduledUptimeMs: noteOffTime)
                }

            case .slide(let fromItem, let toItem, let offTimeMs):
                guard let startMidi = midiNoteNumber(for: fromItem.pitch, octave: fromItem.octave),
                      let endMidi = midiNoteNumber(for: toItem.pitch, octave: toItem.octave) else { continue }
                note = startMidi
                let noteOnTime = startTimeMs + Double(fromItem.position) * msPerStep
                let noteOffTime = startTimeMs + offTimeMs * 0.98
                onId = midiManager.scheduleNoteOn(note: startMidi, velocity: 100, channel: channel, scheduledUptimeMs: noteOnTime)
                offId = midiManager.scheduleNoteOff(note: startMidi, velocity: 0, channel: channel, scheduledUptimeMs: noteOffTime)

                let slideDurationMs = Double(toItem.position - fromItem.position) * msPerStep
                if slideDurationMs > 0 {
                    let semitoneDiff = Int(endMidi) - Int(startMidi)
                    let finalBend = 8192 + Int((Double(semitoneDiff) / 12.0) * 8191.0)
                    let steps = max(2, Int(slideDurationMs / 20))
                    for i in 0...steps {
                        let t = Double(i) / Double(steps)
                        let bendTime = noteOnTime + t * slideDurationMs
                        let value = 8192 + Int(Double(finalBend - 8192) * t)
                        midiManager.schedulePitchBend(value: UInt16(value), channel: channel, scheduledUptimeMs: bendTime)
                    }
                }
                midiManager.schedulePitchBend(value: 8192, channel: channel, scheduledUptimeMs: noteOffTime + 1)

            case .vibrato(let item, let offTimeMs):
                guard let midiNote = midiNoteNumber(for: item.pitch, octave: item.octave) else { continue }
                note = midiNote
                let noteOnTime = startTimeMs + Double(item.position) * msPerStep
                let noteOffTime = startTimeMs + offTimeMs * 0.98
                onId = midiManager.scheduleNoteOn(note: midiNote, velocity: 100, channel: channel, scheduledUptimeMs: noteOnTime)
                offId = midiManager.scheduleNoteOff(note: midiNote, velocity: 0, channel: channel, scheduledUptimeMs: noteOffTime)

                let durationMs = noteOffTime - noteOnTime
                if durationMs > 100 {
                    let rateHz = 5.5
                    let maxBendSemitones = 0.25
                    let maxBend = (maxBendSemitones / 12.0) * 8191.0
                    let cycles = durationMs / 1000.0 * rateHz
                    let steps = Int(cycles * 12.0)
                    if steps > 0 {
                        for i in 0...steps {
                            let t_dur = Double(i) / Double(steps)
                            let t_ang = t_dur * cycles * 2 * .pi
                            let bend = 8192 + Int(sin(t_ang) * maxBend)
                            let bendTime = noteOnTime + t_dur * durationMs
                            midiManager.schedulePitchBend(value: UInt16(bend), channel: channel, scheduledUptimeMs: bendTime)
                        }
                    }
                }
                midiManager.schedulePitchBend(value: 8192, channel: channel, scheduledUptimeMs: noteOffTime + 1)

            case .bend(let item, let offTimeMs):
                guard let midiNote = midiNoteNumber(for: item.pitch, octave: item.octave) else { continue }
                note = midiNote
                let noteOnTime = startTimeMs + Double(item.position) * msPerStep
                let noteOffTime = startTimeMs + offTimeMs * 0.98
                onId = midiManager.scheduleNoteOn(note: midiNote, velocity: 100, channel: channel, scheduledUptimeMs: noteOnTime)
                offId = midiManager.scheduleNoteOff(note: midiNote, velocity: 0, channel: channel, scheduledUptimeMs: noteOffTime)

                let bendDurationMs = 100.0
                if (noteOffTime - noteOnTime) > bendDurationMs {
                    let finalBend = 8192 + Int((1.0 / 12.0) * 8191.0) // 1 semitone bend
                    for i in 0...10 {
                        let t = Double(i) / 10.0
                        let bendTime = noteOnTime + t * bendDurationMs
                        let value = 8192 + Int(Double(finalBend - 8192) * t)
                        midiManager.schedulePitchBend(value: UInt16(value), channel: channel, scheduledUptimeMs: bendTime)
                    }
                }
                midiManager.schedulePitchBend(value: 8192, channel: channel, scheduledUptimeMs: noteOffTime + 1)
            }
            scheduled.append(ScheduledPlaybackNote(note: note, channel: channel, onEventId: onId, offEventId: offId))
        }

        guard !scheduled.isEmpty else { return }
        scheduledPlaybackNotes = scheduled
        isPlayingSegment = true

        // 3. UI Update and Completion Handling (remains mostly the same)
        playbackProgress = 0.0
        cancelProgressTasks()
        let totalDurationMs = Double(totalSteps) * msPerStep
        let completionTask = DispatchWorkItem { stopSegmentPlayback(sendNoteOff: false) }
        playbackCompletionTask = completionTask
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDurationMs / 1000.0 + 0.25, execute: completionTask)

        var tasks: [DispatchWorkItem] = []
        let now = ProcessInfo.processInfo.systemUptime * 1000.0
        for step in 0...totalSteps {
            let stepTimeMs = startTimeMs + Double(step) * msPerStep
            let delaySeconds = max(0, (stepTimeMs - now) / 1000.0)
            let task = DispatchWorkItem {
                guard isPlayingSegment else { return }
                playbackProgress = min(max(Double(step) / Double(totalSteps), 0.0), 1.0)
            }
            tasks.append(task)
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: task)
        }
        playbackProgressTasks = tasks
        // --- End Technique-Aware Playback Logic ---
    }

    private func stopSegmentPlayback(sendNoteOff: Bool = true) {
        playbackCompletionTask?.cancel()
        playbackCompletionTask = nil
        cancelProgressTasks()

        if sendNoteOff {
            for entry in scheduledPlaybackNotes {
                if let onId = entry.onEventId { midiManager.cancelScheduledEvent(id: onId) }
                if let offId = entry.offEventId { midiManager.cancelScheduledEvent(id: offId) }
                midiManager.sendNoteOff(note: entry.note, velocity: 0, channel: entry.channel)
            }
        }

        scheduledPlaybackNotes.removeAll()
        isPlayingSegment = false
        playbackProgress = 0.0
        stopPreview()
    }

    private func previewPitch(pitch: Int, octave: Int) {
        stopPreview()
        guard let midiNote = midiNoteNumber(for: pitch, octave: octave) else { return }
        let channel = UInt8(max(0, min(15, appData.chordMidiChannel - 1)))
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
        let channel = UInt8(max(0, min(15, appData.chordMidiChannel - 1)))
        midiManager.sendNoteOff(note: note, velocity: 0, channel: channel)
        lastPreviewNote = nil
    }

    private func midiNoteNumber(for pitch: Int, octave: Int) -> UInt8? {
        guard pitch >= 1 && pitch <= 7 else { return nil }
        let scaleOffsets = [0, 2, 4, 5, 7, 9, 11]
        let baseC = 60
        let key = appData.preset?.key ?? "C"
        let transpose = transposition(forKey: key)
        let midiValue = baseC + transpose + scaleOffsets[pitch - 1] + octave * 12
        guard midiValue >= 0 && midiValue <= 127 else { return nil }
        return UInt8(midiValue)
    }

    private func transposition(forKey key: String) -> Int {
        let keyMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4,
            "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9,
            "A#": 10, "Bb": 10, "B": 11
        ]
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = trimmed.uppercased()
        let simplified = uppercased.hasSuffix("M") && uppercased.count > 1 ? String(uppercased.dropLast()) : uppercased
        return keyMap[simplified] ?? 0
    }

    private func cancelProgressTasks() {
        playbackProgressTasks.forEach { $0.cancel() }
        playbackProgressTasks.removeAll()
    }

    private struct ScheduledPlaybackNote {
        let note: UInt8
        let channel: UInt8
        let onEventId: UUID?
        let offEventId: UUID?
    }
}

// MARK: - Subviews

struct MelodicLyricToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var gridSizeInSteps: Int
    @Binding var zoomLevel: CGFloat
    @Binding var segmentLengthInBars: Int
    @State private var showingSettings = false
    let isPlayingSegment: Bool
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
                LyricSegmentSettingsView(lengthInBars: $segmentLengthInBars)
            }
        }.pickerStyle(.menu)
    }
}

struct LyricSegmentSettingsView: View {
    @Binding var lengthInBars: Int
    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties").font(.headline)
            HStack {
                Text("Length (bars):")
                TextField("Length", value: $lengthInBars, format: .number).frame(width: 60)
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
            for step in stride(from: 0, through: totalSteps, by: gridSizeInSteps) {
                let x = CGFloat(step) * stepWidth
                let isBeatLine = step % stepsPerBeat == 0
                let isBarLine = isBeatLine && (step / stepsPerBeat) % beatsPerBar == 0
                let lineColor: Color = isBarLine ? .primary.opacity(0.8) : (isBeatLine ? .primary.opacity(0.5) : .primary.opacity(0.2))
                let lineWidth: CGFloat = isBarLine ? 1.0 : 0.5
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: trackHeight)) }, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
    }
}

struct MelodicLyricCellView: View {
    let item: MelodicLyricItem
    let isSelected: Bool
    let stepWidth: CGFloat

    // Dynamically calculate font sizes based on the cell's width
    private var pitchFontSize: CGFloat {
        return max(8, min(24, stepWidth * 0.6))
    }

    private var wordFontSize: CGFloat {
        return max(6, min(16, stepWidth * 0.4))
    }

    private var techniqueFontSize: CGFloat {
        return max(5, min(12, stepWidth * 0.3))
    }

    var body: some View {
        let textColor = isSelected ? Color.white : Color.primary
        VStack(spacing: 2) {
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
        .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1, y: 1)
        .frame(width: stepWidth - 2) // Leave a small gap between cells
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
