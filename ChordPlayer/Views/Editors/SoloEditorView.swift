import SwiftUI
import Combine

struct SoloEditorView: View {
    @EnvironmentObject var soloPlayer: SoloPlayer
    @EnvironmentObject var appData: AppData
    
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

    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let beatWidth: CGFloat = 80
    private let stringHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            if isEditingName {
                TextField("Segment Name", text: $soloSegment.name)
                    .font(.largeTitle)
                    .textFieldStyle(.plain)
                    .padding()
                    .focused($isNameFieldFocused)
                    .onSubmit { isEditingName = false }
                    .onDisappear { isEditingName = false } // Ensure editing stops if view disappears
            } else {
                Text(soloSegment.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                    .onTapGesture(count: 2) {
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
                isPlaying: .constant(soloPlayer.isPlaying),
                playbackPosition: .constant(soloPlayer.playbackPosition),
                segmentLength: $soloSegment.lengthInBeats,
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
                    currentTechnique: currentTechnique,
                    currentFret: currentFret,
                    gridSize: gridSize,
                    zoomLevel: zoomLevel,
                    isPlaying: soloPlayer.isPlaying,
                    playbackPosition: soloPlayer.playbackPosition,
                    beatWidth: beatWidth,
                    stringHeight: stringHeight,
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
                            if let nextIdx = findPrecedingNoteIndex(before: Double.greatestFiniteMagnitude, on: soloSegment.notes[idx].string) {
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
        .onKeyDown { event in handleKeyDown(event) }
        .onDisappear(perform: { soloPlayer.stopPlayback() })
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
        soloPlayer.play(segment: soloSegment, quantization: .none, channel: midiChannel)
    }

    private func notifyChanges() {
        appData.updateSoloSegment(soloSegment)
    }

    // MARK: - Note Editing Logic
    // MARK: - Note Editing Logic

    // MARK: - Note Editing Logic

    private func updateSelectedNote(change: (inout SoloNote) -> Void) {
        if selectedNotes.count == 1, let index = soloSegment.notes.firstIndex(where: { $0.id == selectedNotes.first! }) {
            change(&soloSegment.notes[index])
        }
    }

    /// The main entry point for all tap interactions on the grid.
    private func handleGridTap(at position: CGPoint? = nil, onNote noteID: UUID? = nil) {
        // This is the unified handler for all tap gestures on the grid.
        
        // Case 1: A note was tapped directly.
        if let noteID = noteID {
            // Simple behavior: tapping a note selects it
            selectNote(noteID)
            return
        }
        
        // Case 2: A blank space on the grid was tapped.
        if let position = position {
            let stringLabelWidth: CGFloat = 40.0
            let stringIndex = Int(position.y / stringHeight)
            let time = Double((position.x - stringLabelWidth) / beatWidth) / Double(zoomLevel)
            guard stringIndex >= 0 && stringIndex < 6 && time >= 0 else { return }
            let tappedTime = snapToGrid(time)

            // Default behavior: if a note exists at this grid position, select it. Otherwise add a new note.
            if let existingNote = soloSegment.notes.first(where: { $0.string == stringIndex && tappedTime >= $0.startTime && tappedTime < ($0.startTime + ($0.duration ?? gridSize)) }) {
                selectNote(existingNote.id)
            } else {
                addNote(at: tappedTime, on: stringIndex)
            }
        }
    }

    private func addNote(at time: Double, on stringIndex: Int) {
        print("[DEBUG] addNote called at time: \(time), string: \(stringIndex)")
        if soloSegment.notes.contains(where: { $0.string == stringIndex && abs($0.startTime - time) < 0.001 }) {
            return
        }
        
        let newNote = SoloNote(startTime: time, duration: 1.0, string: stringIndex, fret: currentFret, technique: currentTechnique)
        soloSegment.notes.append(newNote)
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
    
    private func selectNote(_ noteId: UUID, addToSelection: Bool = false) {
        if addToSelection {
            if selectedNotes.contains(noteId) { selectedNotes.remove(noteId) } else { selectedNotes.insert(noteId) }
        } else {
            selectedNotes = [noteId]
        }
    }
    
    private func deleteSelectedNotes() {
        soloSegment.notes.removeAll { selectedNotes.contains($0.id) }
        selectedNotes.removeAll()
    }
    
    private func snapToGrid(_ time: Double) -> Double { floor(time / gridSize) * gridSize }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 51: // Backspace/Delete
            deleteSelectedNotes()
            return true
        case 49: // Spacebar
            playToggle()
            return true
        default:
            // Check for numeric input for fret setting
            if let chars = event.characters, let _ = Int(chars) {
                fretInputCancellable?.cancel()
                fretInputBuffer += chars
                
                if fretInputBuffer.count >= 2 {
                    commitFretInput()
                } else {
                    fretInputCancellable = Just(())
                        .delay(for: .milliseconds(400), scheduler: DispatchQueue.main)
                        .sink { [self] in commitFretInput() }
                }
                return true
            }
            return false
        }
    }
    
    private func commitFretInput() {
        if let fret = Int(fretInputBuffer), (0...24).contains(fret) {
            self.currentFret = fret
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
    
    @State private var showingSettings: Bool = false

    let onPlay: () -> Void
    let onSetFret: () -> Void
    
    private let durations: [(String, Double)] = [("1/1", 1.0), ("1/2", 0.5), ("1/4", 0.25), ("1/8", 0.125), ("1/16", 0.0625)]
    
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
                    ForEach(durations, id: \.1) { name, value in
                        Label(name, systemImage: "squareshape.split.2x2").tag(value)
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
                SegmentSettingsView(lengthInBeats: $segmentLength, midiChannel: $midiChannel)
            }
        }
        .textFieldStyle(.roundedBorder)
        .pickerStyle(.menu)
    }
}

struct SoloTablatureView: View {
    @Binding var soloSegment: SoloSegment
    @Binding var selectedNotes: Set<UUID>
    
    let currentTechnique: PlayingTechnique
    let currentFret: Int
    let gridSize: Double
    let zoomLevel: CGFloat
    let isPlaying: Bool
    let playbackPosition: Double
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    
    let onNoteSelect: (UUID, Bool) -> Void
    let onNoteDelete: () -> Void
    let onNoteTap: (UUID) -> Void
    let onBackgroundTap: (CGPoint) -> Void
    let onNoteResize: (UUID, Double) -> Void
    let onSetFret: () -> Void
    
    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            SoloGridView(lengthInBeats: soloSegment.lengthInBeats, gridSize: gridSize, beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel)
            
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

// Other subviews (SoloGridView, SoloStringLineView, etc.) remain unchanged.

struct SoloGridView: View {
    let lengthInBeats: Double, gridSize: Double, beatWidth: CGFloat, stringHeight: CGFloat, zoomLevel: CGFloat
    let beatsPerBar: Int = 4 // Assuming 4/4 time signature

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
    private let beatsPerBar: Int = 4

    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties").font(.headline)
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
            let currentBars = lengthInBeats / Double(beatsPerBar)
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