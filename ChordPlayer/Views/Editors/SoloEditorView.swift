import SwiftUI
import Combine

struct SoloEditorView: View {
    @EnvironmentObject var soloPlayer: SoloPlayer
    @EnvironmentObject var midiSequencer: MIDISequencer
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    
    @Binding var soloSegment: SoloSegment
    @State private var selectedNotes: Set<UUID> = []
    
    // Editing state
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var currentFret: Int = 0
    @State private var gridSize: Double = 0.25
    @State private var zoomLevel: CGFloat = 1.0
    @State private var midiChannel: UInt8 = 0

    // State for fret input
    @State private var fretInputBuffer: String = ""
    @State private var fretInputCancellable: AnyCancellable? = nil
    @State private var showingFretPopover: Bool = false

    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var temporaryName: String = ""
    
    // Keyboard navigation state
    @State private var activeCell: GridPosition = GridPosition(stringIndex: 0, timeStep: 0)
    @FocusState private var isGridFocused: Bool


    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let beatWidth: CGFloat = 80
    private let stringHeight: CGFloat = 40

    private var beatsPerBar: Int {
        appData.preset?.timeSignature.beatsPerMeasure ?? 4
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEditingName {
                TextField("Segment Name", text: $temporaryName)
                    .font(.largeTitle)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding()
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        soloSegment.name = temporaryName
                        isEditingName = false
                    }
                    .onDisappear { isEditingName = false } // Ensure editing stops if view disappears
            } else {
                Text(soloSegment.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                    .onTapGesture(count: 2) {
                        temporaryName = soloSegment.name
                        isEditingName = true
                        isNameFieldFocused = true
                    }
            }

            SoloToolbar(
                currentTechnique: $currentTechnique,
                currentFret: $currentFret,
                gridSize: $gridSize,
                zoomLevel: $zoomLevel,
                midiChannel: $midiChannel,
                isPlaying: $soloPlayer.isPlaying,
                playbackPosition: $midiSequencer.currentTimeInBeats,
                segmentLength: $soloSegment.lengthInBeats,
                beatsPerBar: beatsPerBar,
                onPlay: playToggle,
                onSetFret: { showingFretPopover = true }
            )
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollView([.horizontal, .vertical]) {
                SoloTablatureView(
                    soloSegment: $soloSegment,
                    selectedNotes: $selectedNotes,
                    activeCell: $activeCell,
                    currentTechnique: currentTechnique,
                    currentFret: currentFret,
                    gridSize: gridSize,
                    zoomLevel: zoomLevel,
                    isPlaying: soloPlayer.isPlaying,
                    playbackPosition: midiSequencer.currentTimeInBeats,
                    beatWidth: beatWidth,
                    stringHeight: stringHeight,
                    beatsPerBar: beatsPerBar,
                    onNoteSelect: selectNote,
                    onNoteDelete: deleteSelectedNotes,
                    onNoteTap: { noteId in selectNote(noteId) },
                    onBackgroundTap: { position in handleGridTap(at: position) },
                    onNoteResize: { noteId, newDuration in
                        // Handle resizing from note view drag handle: snap, clamp against next note, enforce min gridSize
                        if let idx = soloSegment.notes.firstIndex(where: { $0.id == noteId }) {
                            let start = soloSegment.notes[idx].startTime
                            // clamp to not overlap next note on same string
                            var maxDuration: Double = soloSegment.lengthInBeats - start
                            if let _ = findPrecedingNoteIndex(before: Double.greatestFiniteMagnitude, on: soloSegment.notes[idx].string) {
                                // find next note after this one on same string
                                let candidates = soloSegment.notes.indices.filter { soloSegment.notes[$0].string == soloSegment.notes[idx].string && soloSegment.notes[$0].startTime > start }
                                if let next = candidates.min(by: { soloSegment.notes[$0].startTime < soloSegment.notes[$1].startTime }) {
                                    maxDuration = soloSegment.notes[next].startTime - start
                                }
                            }
                            var snapped = snapToGrid(newDuration)
                            snapped = max(gridSize, min(snapped, maxDuration))
                            soloSegment.notes[idx].duration = snapped
                            selectedNotes = [noteId]
                        }
                    },
                    onSetFret: { showingFretPopover = true }
                )
                .frame(
                    width: max(600, 40.0 + beatWidth * CGFloat(soloSegment.lengthInBeats) * zoomLevel),
                    height: stringHeight * 6 + 100
                )
            }
            .background(Color(NSColor.textBackgroundColor))
            .focused($isGridFocused)
            .onTapGesture {
                isGridFocused = true
            }
            .onChange(of: activeCell) { _, _ in
                updateSelectionForActiveCell()
            }
            
            Divider()
            
            HStack {
                Text("Selected: \(selectedNotes.count) notes")
                Spacer()
                Text("Length: \(String(format: "%.1f", soloSegment.lengthInBeats)) beats")
                Spacer()
                Text("Notes: \(soloSegment.notes.count)")
            }
            .padding(.horizontal)
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            isGridFocused = true
        }
        .onChange(of: soloPlayer.isPlaying) { _, newValue in
            print("[SoloEditorView] Detected change: soloPlayer.isPlaying is now \(newValue)")
        }
        .onKeyDown { event in handleKeyDown(event) }
        .onDisappear(perform: { soloPlayer.stop() })
        .onChange(of: soloSegment) { notifyChanges() }
        .onChange(of: selectedNotes) {
            if selectedNotes.count == 1, let selectedNote = soloSegment.notes.first(where: { $0.id == selectedNotes.first! }) {
                currentFret = selectedNote.fret
                currentTechnique = selectedNote.technique
            }
        }
        .onChange(of: currentFret) { updateSelectedNote { $0.fret = currentFret } }
        .onChange(of: currentTechnique) { updateSelectedNote { $0.technique = currentTechnique } }
        .popover(isPresented: $showingFretPopover, arrowEdge: .bottom) {
            FretInputPopover(currentFret: $currentFret, onCommit: { showingFretPopover = false })
        }
    }
    
    // MARK: - Actions
    private func playToggle() {
        soloPlayer.play(segment: soloSegment, channel: midiChannel)
    }

    private func notifyChanges() {
        appData.updateSoloSegment(soloSegment)
    }

    private func playNoteFeedback(note: SoloNote) {
        // Standard tuning MIDI notes for open strings EADGBe (6 to 1)
        let baseMidiNotes = [64, 59, 55, 50, 45, 40]
        guard note.string >= 0 && note.string < baseMidiNotes.count else { return }

        let midiNoteNumber = baseMidiNotes[note.string] + note.fret
        guard midiNoteNumber >= 0 && midiNoteNumber <= 127 else { return }

        let velocity = note.velocity
        
        midiManager.sendNoteOn(note: UInt8(midiNoteNumber), velocity: UInt8(velocity), channel: midiChannel)
        
        // Schedule Note Off after a short duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.midiManager.sendNoteOff(note: UInt8(midiNoteNumber), velocity: 0, channel: self.midiChannel)
        }
    }
    
    private func updateSelectionForActiveCell() {
        let activeTime = Double(activeCell.timeStep) * gridSize
        if let noteAtCell = soloSegment.notes.first(where: { $0.string == activeCell.stringIndex && abs($0.startTime - activeTime) < 0.001 }) {
            selectedNotes = [noteAtCell.id]
        } else {
            selectedNotes = []
        }
    }

    // MARK: - Note Editing Logic
    // MARK: - Note Editing Logic
    // MARK: - Note Editing Logic

    private func updateSelectedNote(change: (inout SoloNote) -> Void) {
        if selectedNotes.count == 1, let index = soloSegment.notes.firstIndex(where: { $0.id == selectedNotes.first! }) {
            let originalNote = soloSegment.notes[index]
            
            var changedNote = originalNote
            change(&changedNote)

            // Only update and play feedback if the note has actually changed.
            if changedNote.fret != originalNote.fret || changedNote.technique != originalNote.technique {
                soloSegment.notes[index] = changedNote
                playNoteFeedback(note: changedNote)
            }
        }
    }

    /// The main entry point for all tap interactions on the grid.
    private func handleGridTap(at position: CGPoint) {
        let stringLabelWidth: CGFloat = 40.0
        let stringIndex = Int(position.y / stringHeight)
        let timeInBeats = Double((position.x - stringLabelWidth) / beatWidth) / Double(zoomLevel)
        
        guard stringIndex >= 0 && stringIndex < 6 && timeInBeats >= 0 else { return }
        
        let timeStep = Int(floor(timeInBeats / gridSize))
        let tappedTime = Double(timeStep) * gridSize
        
        // Update active cell based on tap
        self.activeCell = GridPosition(stringIndex: stringIndex, timeStep: timeStep)

        // If a note exists at this grid position, select it. Otherwise, do nothing.
        if let existingNote = soloSegment.notes.first(where: { $0.string == stringIndex && tappedTime >= $0.startTime && tappedTime < ($0.startTime + ($0.duration ?? gridSize)) }) {
            selectNote(existingNote.id)
        }
    }

    private func addNote(at time: Double, on stringIndex: Int) {
        print("[DEBUG] addNote called at time: \(time), string: \(stringIndex)")
        // Prevent adding a note if one already exists at the exact start time
        if soloSegment.notes.contains(where: { $0.string == stringIndex && abs($0.startTime - time) < 0.001 }) {
            // If a note exists, select it instead of adding a new one
            if let existingNote = soloSegment.notes.first(where: { $0.string == stringIndex && abs($0.startTime - time) < 0.001 }) {
                selectNote(existingNote.id)
            }
            return
        }
        
        let newNote = SoloNote(startTime: time, duration: gridSize, string: stringIndex, fret: currentFret, technique: currentTechnique)
        soloSegment.notes.append(newNote)
        playNoteFeedback(note: newNote)
        recalculateDurations(forString: stringIndex)
        selectedNotes = [newNote.id]
    }

    private func findPrecedingNoteIndex(before time: Double, on stringIndex: Int) -> Int? {
        soloSegment.notes.indices.filter {
            soloSegment.notes[$0].string == stringIndex && soloSegment.notes[$0].startTime < time
        }.max(by: { soloSegment.notes[$0].startTime < soloSegment.notes[$1].startTime })
    }

    private func recalculateDurations(forString stringIndex: Int) {
        let notesOnStringIndices = soloSegment.notes.indices
            .filter { soloSegment.notes[$0].string == stringIndex }
            .sorted { soloSegment.notes[$0].startTime < soloSegment.notes[$1].startTime }

        for i in 0..<notesOnStringIndices.count - 1 {
            let currentIndex = notesOnStringIndices[i]
            let nextIndex = notesOnStringIndices[i+1]
            
            let currentNote = soloSegment.notes[currentIndex]
            let nextNote = soloSegment.notes[nextIndex]
            
            if let currentDuration = currentNote.duration {
                if currentNote.startTime + currentDuration > nextNote.startTime {
                    soloSegment.notes[currentIndex].duration = nextNote.startTime - currentNote.startTime
                }
            } else {
                 soloSegment.notes[currentIndex].duration = nextNote.startTime - currentNote.startTime
            }
        }
    }
    
    private func toggleTechniqueOnActiveCell(_ technique: PlayingTechnique) {
        let activeTime = Double(activeCell.timeStep) * gridSize
        if let index = soloSegment.notes.firstIndex(where: { $0.string == activeCell.stringIndex && abs($0.startTime - activeTime) < 0.001 }) {
            var note = soloSegment.notes[index]
            note.technique = (note.technique == technique) ? .normal : technique
            soloSegment.notes[index] = note
            playNoteFeedback(note: note)
        }
    }
    
    private func selectNote(_ noteId: UUID, addToSelection: Bool = false) {
        if addToSelection {
            if selectedNotes.contains(noteId) { selectedNotes.remove(noteId) } else { selectedNotes.insert(noteId) }
        } else {
            selectedNotes = [noteId]
            // Also update active cell when a note is selected
            if let note = soloSegment.notes.first(where: { $0.id == noteId }) {
                activeCell = GridPosition(stringIndex: note.string, timeStep: Int(note.startTime / gridSize))
            }
        }
    }
    
    private func deleteSelectedNotes() {
        soloSegment.notes.removeAll { selectedNotes.contains($0.id) }
        selectedNotes.removeAll()
    }
    
    private func snapToGrid(_ time: Double) -> Double { floor(time / gridSize) * gridSize }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if isNameFieldFocused { return false } // Don't interfere with name editing

        // Arrow key navigation
        switch event.keyCode {
        case 126: // Up Arrow
            activeCell.stringIndex = max(0, activeCell.stringIndex - 1)
            return true
        case 125: // Down Arrow
            activeCell.stringIndex = min(5, activeCell.stringIndex + 1)
            return true
        case 123: // Left Arrow
            activeCell.timeStep = max(0, activeCell.timeStep - 1)
            return true
        case 124: // Right Arrow
            let maxTimeStep = Int(soloSegment.lengthInBeats / gridSize) - 1
            activeCell.timeStep = min(maxTimeStep, activeCell.timeStep + 1)
            return true
        case 51: // Backspace/Delete
            deleteSelectedNotes()
            return true
        case 49: // Spacebar
            playToggle()
            return true
        default:
            break // Continue to character processing
        }
        
        // Character-based input
        if let chars = event.characters, let firstChar = chars.first {
            // Numeric input for fret setting
            if firstChar.isNumber {
                fretInputCancellable?.cancel()
                fretInputBuffer += String(firstChar)
                
                // Use a timer to handle multi-digit input
                fretInputCancellable = Just(()).delay(for: .milliseconds(400), scheduler: DispatchQueue.main).sink { [self] in
                    commitFretInput(at: activeCell)
                }
                return true
            }
            
            // Technique and other commands
            switch firstChar {
            case "/": toggleTechniqueOnActiveCell(.slide)
            case "^": toggleTechniqueOnActiveCell(.bend)
            case "~": toggleTechniqueOnActiveCell(.vibrato)
            case "p": toggleTechniqueOnActiveCell(.pullOff)
            case "-":
                // Create a tie/sustain from the previous note to the END of the active cell
                let activeStartTime = Double(activeCell.timeStep) * gridSize
                let activeEndTime = activeStartTime + gridSize // The end time of the active cell
                if let precedingNoteIndex = findPrecedingNoteIndex(before: activeStartTime, on: activeCell.stringIndex) {
                    let precedingNote = soloSegment.notes[precedingNoteIndex]
                    let newDuration = activeEndTime - precedingNote.startTime
                    if newDuration > 0 {
                        soloSegment.notes[precedingNoteIndex].duration = newDuration
                    }
                }
                return true
            default:
                return false // Not a recognized character
            }
            return true
        }
        
        return false
    }
    
    private func commitFretInput(at position: GridPosition) {
        if let fret = Int(fretInputBuffer), (0...24).contains(fret) {
            let time = Double(position.timeStep) * gridSize
            // Check if a note already exists to update it, otherwise create a new one
            if let index = soloSegment.notes.firstIndex(where: { $0.string == position.stringIndex && abs($0.startTime - time) < 0.001 }) {
                soloSegment.notes[index].fret = fret
                playNoteFeedback(note: soloSegment.notes[index])
                selectedNotes = [soloSegment.notes[index].id]
            } else {
                let newNote = SoloNote(startTime: time, duration: gridSize, string: position.stringIndex, fret: fret, technique: .normal)
                soloSegment.notes.append(newNote)
                playNoteFeedback(note: newNote)
                recalculateDurations(forString: position.stringIndex)
                selectedNotes = [newNote.id]
            }
        }
        fretInputBuffer = ""
        fretInputCancellable = nil
    }
}

// MARK: - Subviews

struct SoloToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var currentFret: Int
    @Binding var gridSize: Double
    @Binding var zoomLevel: CGFloat
    @Binding var midiChannel: UInt8
    @Binding var isPlaying: Bool
    @Binding var playbackPosition: Double
    @Binding var segmentLength: Double
    let beatsPerBar: Int
    
    @State private var showingSettings: Bool = false

    let onPlay: () -> Void
    let onSetFret: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help(isPlaying ? "Stop Playback" : "Play Solo")

            Spacer()

            HStack(spacing: 15) {
                // Tool selection removed: clicking adds/selects, drag handle resizes

                Picker("Technique", selection: $currentTechnique) {
                    ForEach(PlayingTechnique.allCases) { technique in
                        Text(technique.chineseName).tag(technique)
                    }
                }.frame(minWidth: 80).help("Playing Technique")

                Button(action: onSetFret) {
                    Text("Fret: \(currentFret)")
                }
                .help("Set Current Fret (or use number keys)")
            }

            Spacer()

            HStack(spacing: 15) {
                Picker("Grid", selection: $gridSize) {
                    ForEach(GridResolution.allCases, id: \.self) { resolution in
                        Text(resolution.rawValue).tag(1.0 / Double(resolution.stepsPerBeat))
                    }
                }.frame(minWidth: 80).help("Grid Snap")
                
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Slider(value: $zoomLevel, in: 0.5...3.0).frame(width: 100)
                }.help("Zoom Level")
            }
            
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
            }.buttonStyle(.bordered)
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                SegmentSettingsView(lengthInBeats: $segmentLength, midiChannel: $midiChannel, beatsPerBar: beatsPerBar)
            }
        }
        .textFieldStyle(.roundedBorder)
        .pickerStyle(.menu)
    }
}

struct SoloTablatureView: View {
    @Binding var soloSegment: SoloSegment
    @Binding var selectedNotes: Set<UUID>
    @Binding var activeCell: GridPosition
    
    let currentTechnique: PlayingTechnique
    let currentFret: Int
    let gridSize: Double
    let zoomLevel: CGFloat
    let isPlaying: Bool
    let playbackPosition: Double
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    let beatsPerBar: Int
    
    let onNoteSelect: (UUID, Bool) -> Void
    let onNoteDelete: () -> Void
    let onNoteTap: (UUID) -> Void
    let onBackgroundTap: (CGPoint) -> Void
    let onNoteResize: (UUID, Double) -> Void
    let onSetFret: () -> Void
    
    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            SoloGridView(lengthInBeats: soloSegment.lengthInBeats, gridSize: gridSize, beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel, beatsPerBar: beatsPerBar)
            
            ActiveCellHighlightView(activeCell: activeCell, beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel, gridSize: gridSize)
            
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { stringIndex in
                    SoloStringLineView(stringIndex: stringIndex, stringName: stringNames[stringIndex], lengthInBeats: soloSegment.lengthInBeats, beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel)
                }
            }
            
            ForEach(soloSegment.notes) { note in
                SoloNoteView(note: note, isSelected: selectedNotes.contains(note.id), beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel) { newDuration in
                    onNoteResize(note.id, newDuration)
                }
                .onTapGesture {
                    onNoteTap(note.id)
                }
            }
            
            if isPlaying && playbackPosition > 0 {
                let stringLabelWidth: CGFloat = 40.0
                Rectangle().fill(Color.red).frame(width: 2)
                    .offset(x: stringLabelWidth + CGFloat(playbackPosition) * beatWidth * zoomLevel)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            onBackgroundTap(location)
        }
        .contextMenu {
            Button("Set Current Fret", action: onSetFret)
        }
    }
}

struct FretInputPopover: View {
    @Binding var currentFret: Int
    let onCommit: () -> Void
    @FocusState private var isFretFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("Set Current Fret").font(.headline)
            TextField("Fret", value: $currentFret, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .labelsHidden()
                .focused($isFretFieldFocused)
                .onAppear { isFretFieldFocused = true }
            
            Button("Done", action: onCommit)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

// MARK: - Helper Structs & Views

struct GridPosition: Equatable, Hashable {
    var stringIndex: Int
    var timeStep: Int
}

struct ActiveCellHighlightView: View {
    let activeCell: GridPosition
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    let zoomLevel: CGFloat
    let gridSize: Double
    
    private let stringLabelWidth: CGFloat = 40.0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .frame(width: beatWidth * gridSize * zoomLevel, height: stringHeight)
            .position(
                x: stringLabelWidth + (CGFloat(activeCell.timeStep) * beatWidth * gridSize * zoomLevel) + (beatWidth * gridSize * zoomLevel / 2),
                y: CGFloat(activeCell.stringIndex) * stringHeight + stringHeight / 2
            )
    }
}


// Other subviews (SoloGridView, SoloStringLineView, etc.) remain unchanged.

struct SoloGridView: View {
    let lengthInBeats: Double, gridSize: Double, beatWidth: CGFloat, stringHeight: CGFloat, zoomLevel: CGFloat
    let beatsPerBar: Int

    var body: some View {
        Canvas { context, size in
            let stringLabelWidth: CGFloat = 40.0
            let totalHeight = stringHeight * 6
            var beat = 0.0
            
            while beat <= lengthInBeats {
                let x = stringLabelWidth + CGFloat(beat) * beatWidth * zoomLevel
                
                let isBarLine = beat.truncatingRemainder(dividingBy: Double(beatsPerBar)) == 0
                let isBeatLine = beat.truncatingRemainder(dividingBy: 1.0) == 0

                var finalColor: Color = .secondary.opacity(0.3)
                var finalLineWidth: CGFloat = 0.5

                if isBarLine {
                    finalColor = .primary.opacity(0.8)
                    finalLineWidth = 1.2
                } else if isBeatLine {
                    finalColor = .secondary.opacity(0.7)
                    finalLineWidth = 0.8
                }
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: totalHeight))
                    },
                    with: .color(finalColor),
                    lineWidth: finalLineWidth
                )
                
                beat += gridSize
            }
        }
    }
}

struct SoloStringLineView: View {
    let stringIndex: Int, stringName: String, lengthInBeats: Double, beatWidth: CGFloat, stringHeight: CGFloat, zoomLevel: CGFloat
    
    var body: some View {
        HStack(spacing: 10) {
            Text(stringName).font(.system(size: 14, weight: .medium)).frame(width: 30, height: stringHeight).background(Color(NSColor.controlBackgroundColor))
            Rectangle().fill(Color.primary).frame(width: beatWidth * CGFloat(lengthInBeats) * zoomLevel, height: 1).frame(height: stringHeight)
        }
    }
}

struct SoloNoteView: View {
    let note: SoloNote, isSelected: Bool, beatWidth: CGFloat, stringHeight: CGFloat, zoomLevel: CGFloat
    // callback when user resizes note via handle; newDuration is in beats
    var onResize: ((Double) -> Void)? = nil

    private var noteColor: Color {
        switch note.technique {
        case .normal: return isSelected ? Color.accentColor : Color.green.opacity(0.7)
        case .slide: return isSelected ? Color.accentColor : Color.blue.opacity(0.7)
        case .bend: return isSelected ? Color.accentColor : Color.orange.opacity(0.7)
        case .vibrato: return isSelected ? Color.accentColor : Color.purple.opacity(0.7)
        case .pullOff: return isSelected ? Color.accentColor : Color.red.opacity(0.7) // 使用红色表示勾弦技巧
        }
    }

    var body: some View {
        let noteDuration = note.duration ?? 1.0
        let noteWidth = CGFloat(noteDuration) * beatWidth * zoomLevel

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(noteColor)
                .frame(width: noteWidth, height: stringHeight * 0.8)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.8), lineWidth: isSelected ? 2 : 1)
                )
            
            HStack(spacing: 2) {
                Text("\(note.fret)")
                Text(note.technique.symbol)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.leading, 5)
        }
        .position(x: 40 + (CGFloat(note.startTime) * beatWidth * zoomLevel) + (noteWidth / 2), y: CGFloat(note.string) * stringHeight + stringHeight / 2)
        .allowsHitTesting(true)
        .overlay(
            // Resize handle on the tail when selected
            Group {
                if isSelected {
                    let handleSize: CGFloat = 10
                    let tailX = 40 + (CGFloat(note.startTime + (note.duration ?? 1.0)) * beatWidth * zoomLevel)
                    Circle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(radius: 1)
                        .position(x: tailX, y: CGFloat(note.string) * stringHeight + stringHeight / 2)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // calculate new duration from dragged x delta
                                let stringLabelWidth: CGFloat = 40.0
                                let localX = value.location.x
                                var time = Double((localX - stringLabelWidth) / beatWidth) / Double(zoomLevel)
                                if time < note.startTime + 0.0625 { time = note.startTime + 0.0625 }
                                let newDuration = time - note.startTime
                                onResize?(newDuration)
                            }
                        )
                }
            }
        )
    }
}

struct SegmentSettingsView: View {
    @Binding var lengthInBeats: Double
    @Binding var midiChannel: UInt8
    @State private var lengthInBarsString: String = ""
    let beatsPerBar: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties (BPB: \(beatsPerBar))").font(.headline)
            HStack {
                Text("Length (bars):")
                TextField("Length", text: $lengthInBarsString)
                    .frame(width: 60)
                    .onSubmit(commitLengthChange)
            }
            HStack {
                Text("MIDI Channel:")
                Picker("MIDI Channel", selection: $midiChannel) {
                    ForEach(0..<16) { channel in
                        Text("\(channel + 1)").tag(UInt8(channel))
                    }
                }
                .labelsHidden()
            }
        }.padding()
        .onAppear {
            let currentBars = (beatsPerBar > 0) ? lengthInBeats / Double(beatsPerBar) : 0
            lengthInBarsString = String(format: "%.2f", currentBars).trimmingCharacters(in: ["0", "."]) // Clean up trailing .00 or .X0
            if lengthInBarsString.isEmpty { lengthInBarsString = "0" }
        }
    }
    
    private func commitLengthChange() {
        if let bars = Double(lengthInBarsString) {
            let newLength = max(0, bars * Double(beatsPerBar))
            lengthInBeats = newLength
        }
    }
}