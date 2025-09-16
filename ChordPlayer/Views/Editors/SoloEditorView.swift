import SwiftUI
import Combine

struct SoloEditorView: View {
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var appData: AppData
    
    @Binding var soloSegment: SoloSegment
    @State private var selectedNotes: Set<UUID> = []
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var currentFret: Int = 0
    @State private var gridSize: Double = 0.25 // 四分音符网格
    @State private var zoomLevel: CGFloat = 1.0
    
    // Playback State
    @State private var isPlaying: Bool = false
    @State private var playbackPosition: Double = 0
    @State private var scheduledEventIDs: [UUID] = []
    @State private var playbackStartDate: Date?
    @State private var uiTimerCancellable: AnyCancellable?

    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let beatWidth: CGFloat = 80
    private let stringHeight: CGFloat = 40
    
    // MIDI note number for open strings, from high E (string 0) to low E (string 5)
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

    var body: some View {
        VStack(spacing: 0) {
            SoloToolbar(
                currentTechnique: $currentTechnique,
                currentFret: $currentFret,
                gridSize: $gridSize,
                zoomLevel: $zoomLevel,
                isPlaying: $isPlaying,
                playbackPosition: $playbackPosition,
                segmentLength: $soloSegment.lengthInBeats,
                onPlay: playToggle
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
                    isPlaying: isPlaying,
                    playbackPosition: playbackPosition,
                    beatWidth: beatWidth,
                    stringHeight: stringHeight,
                    onNoteSelect: selectNote,
                    onNoteDelete: deleteSelectedNotes,
                    onBackgroundTap: handleBackgroundTap
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
        .onDisappear(perform: stopPlayback)
        .onChange(of: selectedNotes) {
            if selectedNotes.count == 1, let selectedNote = soloSegment.notes.first(where: { $0.id == selectedNotes.first! }) {
                currentFret = selectedNote.fret
                currentTechnique = selectedNote.technique
            }
        }
        .onChange(of: currentFret) { updateSelectedNote { $0.fret = currentFret } }
        .onChange(of: currentTechnique) { updateSelectedNote { $0.technique = currentTechnique } }
    }
    
    // MARK: - Playback Logic
    private func playToggle() {
        isPlaying.toggle()
        if isPlaying {
            play()
        } else {
            stopPlayback()
        }
    }

    private func play() {
        stopPlayback() // Ensure everything is clean before starting
        isPlaying = true

        let bpm = appData.preset?.bpm ?? 120.0
        let beatsToSeconds = 60.0 / bpm
        let playbackStartTimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        
        let notesByString = Dictionary(grouping: soloSegment.notes, by: { $0.string })
        var allNoteEvents: [(onTime: Double, offTime: Double, note: SoloNote)] = []

        for (_, notesOnString) in notesByString {
            let sorted = notesOnString.sorted { $0.startTime < $1.startTime }
            if sorted.isEmpty { continue }

            var offTimeCache: [UUID: Double] = [:]

            func getNoteOffTime(for noteIndex: Int) -> Double {
                let note = sorted[noteIndex]
                if let cachedOffTime = offTimeCache[note.id] { return cachedOffTime }
                let nextNoteIndex = noteIndex + 1
                var offTime = soloSegment.lengthInBeats
                if nextNoteIndex < sorted.count {
                    let nextNote = sorted[nextNoteIndex]
                    if nextNote.technique == .hammer || nextNote.technique == .pullOff {
                        offTime = getNoteOffTime(for: nextNoteIndex)
                    } else {
                        offTime = nextNote.startTime
                    }
                }
                offTimeCache[note.id] = offTime
                return offTime
            }

            for i in 0..<sorted.count {
                let note = sorted[i]
                allNoteEvents.append((onTime: note.startTime, offTime: getNoteOffTime(for: i), note: note))
            }
        }

        var eventIDs: [UUID] = []
        for event in allNoteEvents {
            guard event.note.fret >= 0 else { continue }
            let midiNoteNumber = midiNote(from: event.note.string, fret: event.note.fret)
            let velocity = UInt8(event.note.velocity)
            let noteOnTimeMs = playbackStartTimeMs + (event.onTime * beatsToSeconds * 1000.0)
            let noteOffTimeMs = playbackStartTimeMs + (event.offTime * beatsToSeconds * 1000.0)

            if noteOffTimeMs > noteOnTimeMs {
                let onID = midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs)
                eventIDs.append(onID)
                let offID = midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs)
                eventIDs.append(offID)
            }
        }
        self.scheduledEventIDs = eventIDs

        self.playbackStartDate = Date()
        self.uiTimerCancellable = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { _ in
            guard let startDate = self.playbackStartDate else { return }
            let elapsedSeconds = Date().timeIntervalSince(startDate)
            let beatsPerSecond = bpm / 60.0
            self.playbackPosition = elapsedSeconds * beatsPerSecond
            if self.playbackPosition > soloSegment.lengthInBeats { stopPlayback() }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        midiManager.cancelAllPendingScheduledEvents()
        midiManager.sendPanic()
        scheduledEventIDs.removeAll()
        uiTimerCancellable?.cancel()
        playbackStartDate = nil
        playbackPosition = 0
    }
    
    private func midiNote(from string: Int, fret: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        return openStringMIDINotes[string] + UInt8(fret)
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
        case 51: deleteSelectedNotes(); return true
        case 49: playToggle(); return true
        default: return false
        }
    }
}

// MARK: - Subviews (Toolbar, Tablature, etc.)
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
                        Text(technique.symbol.isEmpty ? technique.rawValue : technique.symbol).tag(technique)
                    }
                }.frame(minWidth: 80).help("Playing Technique")

                HStack(spacing: 4) {
                    Image(systemName: "number")
                    TextField("Fret", value: $currentFret, format: .number).frame(width: 40)
                }.help("Fret Number")
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
    }
}

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