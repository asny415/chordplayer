import SwiftUI
import Combine

struct SoloEditorView: View {
    @EnvironmentObject var soloPlayer: SoloPlayer
    @EnvironmentObject var appData: AppData
    
    @Binding var soloSegment: SoloSegment
    @State private var selectedNotes: Set<UUID> = []
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var currentFret: Int = 0
    @State private var gridSize: Double = 0.25
    @State private var zoomLevel: CGFloat = 1.0
    
    // State for fret input
    @State private var fretInputBuffer: String = ""
    @State private var fretInputCancellable: AnyCancellable?
    @State private var showingFretPopover: Bool = false

    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let beatWidth: CGFloat = 80
    private let stringHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            SoloToolbar(
                currentTechnique: $currentTechnique,
                currentFret: $currentFret,
                gridSize: $gridSize,
                zoomLevel: $zoomLevel,
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
                    onBackgroundTap: handleBackgroundTap,
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
        soloPlayer.play(segment: soloSegment, quantization: .none)
    }

    private func notifyChanges() {
        appData.updateSoloSegment(soloSegment)
    }

    // MARK: - Note Editing Logic
    private func handleBackgroundTap(at position: CGPoint) {
        let stringIndex = Int(position.y / stringHeight)
        if stringIndex >= 0 && stringIndex < 6 {
            addNote(at: position)
        } else {
            selectedNotes.removeAll()
        }
    }
    
    private func updateSelectedNote(change: (inout SoloNote) -> Void) {
        if selectedNotes.count == 1, let index = soloSegment.notes.firstIndex(where: { $0.id == selectedNotes.first! }) {
            change(&soloSegment.notes[index])
        }
    }
    
    private func addNote(at position: CGPoint) {
        let stringLabelWidth: CGFloat = 40.0
        let string = Int(position.y / stringHeight)
        let time = Double((position.x - stringLabelWidth) / beatWidth) / Double(zoomLevel)
        
        guard string >= 0 && string < 6 && time >= 0 && time <= soloSegment.lengthInBeats else { return }
        
        let alignedTime = snapToGrid(time)
        let newNote = SoloNote(startTime: alignedTime, string: string, fret: currentFret, technique: currentTechnique)
        
        soloSegment.notes.append(newNote)
        selectedNotes = [newNote.id]
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
    
    private func snapToGrid(_ time: Double) -> Double { round(time / gridSize) * gridSize }
    
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
                SegmentSettingsView(lengthInBeats: $segmentLength)
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
    let onBackgroundTap: (CGPoint) -> Void
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
                SoloNoteView(note: note, isSelected: selectedNotes.contains(note.id), beatWidth: beatWidth, stringHeight: stringHeight, zoomLevel: zoomLevel, onSelect: { onNoteSelect(note.id, $0) })
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
    
    var body: some View {
        Canvas { context, size in
            let stringLabelWidth: CGFloat = 40.0
            let totalHeight = stringHeight * 6
            var beat = 0.0
            while beat <= lengthInBeats {
                let x = stringLabelWidth + CGFloat(beat) * beatWidth * zoomLevel
                let isMainBeat = beat.truncatingRemainder(dividingBy: 1.0) == 0
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: totalHeight)) }, with: .color(isMainBeat ? .secondary : .secondary.opacity(0.5)), lineWidth: isMainBeat ? 1 : 0.5)
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
    let onSelect: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            Text("\(note.fret)").font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor)).overlay(Circle().stroke(Color.primary, lineWidth: 1)))
            
            if !note.technique.symbol.isEmpty {
                Text(note.technique.symbol).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .position(x: 40 + CGFloat(note.startTime) * beatWidth * zoomLevel, y: CGFloat(note.string) * stringHeight + stringHeight / 2)
        .onTapGesture { onSelect(false) }
    }
}

struct SegmentSettingsView: View {
    @Binding var lengthInBeats: Double

    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties").font(.headline)
            HStack {
                Text("Length (beats):")
                TextField("Length", value: $lengthInBeats, format: .number.precision(.fractionLength(1))).frame(width: 60)
            }
        }.padding()
    }
}

// MARK: - KeyDown Handling
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        self.background(KeyEventHandlingView(onKeyDown: action))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView {
        let view = KeyDownView(); view.onKeyDown = onKeyDown; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyDownView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event) { return }
        super.keyDown(with: event)
    }
}