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

    // Musical action definition for playback
    private enum MusicalAction {
        case playNote(note: SoloNote, offTime: Double)
        case slide(from: SoloNote, to: SoloNote, offTime: Double)
        case vibrato(note: SoloNote, offTime: Double)
        case bend(note: SoloNote, offTime: Double)
    }

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
        .onChange(of: soloSegment) { notifyChanges() }
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
        
        let notesSortedByTime = soloSegment.notes.sorted { $0.startTime < $1.startTime }
        var consumedNoteIDs = Set<UUID>()
        var actions: [MusicalAction] = []

        // 1. Pre-process notes to create musical actions
        for i in 0..<notesSortedByTime.count {
            let currentNote = notesSortedByTime[i]
            if consumedNoteIDs.contains(currentNote.id) {
                continue
            }

            var noteOffTime = soloSegment.lengthInBeats
            if let nextNoteOnSameString = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                noteOffTime = nextNoteOnSameString.startTime
            }

            if currentNote.technique == .slide,
               let slideTargetNote = notesSortedByTime.dropFirst(i + 1).first(where: { $0.string == currentNote.string }) {
                
                consumedNoteIDs.insert(slideTargetNote.id)
                
                var slideOffTime = soloSegment.lengthInBeats
                if let targetIndex = notesSortedByTime.firstIndex(of: slideTargetNote), 
                   let nextNoteAfterSlide = notesSortedByTime.dropFirst(targetIndex + 1).first(where: { $0.string == currentNote.string }) {
                    slideOffTime = nextNoteAfterSlide.startTime
                }
                actions.append(.slide(from: currentNote, to: slideTargetNote, offTime: slideOffTime))

            } else if currentNote.technique == .vibrato {
                actions.append(.vibrato(note: currentNote, offTime: noteOffTime))

            } else if currentNote.technique == .bend {
                actions.append(.bend(note: currentNote, offTime: noteOffTime))

            } else { // .normal, or a .slide at the end of a string
                actions.append(.playNote(note: currentNote, offTime: noteOffTime))
            }
        }

        var eventIDs: [UUID] = []
        
        // 2. Process actions and schedule MIDI events
        for action in actions {
            switch action {
            case .playNote(let note, let offTime):
                guard note.fret >= 0 else { continue } // Skip muted notes
                let midiNoteNumber = midiNote(from: note.string, fret: note.fret)
                let velocity = UInt8(note.velocity)

                let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                if noteOffTimeMs > noteOnTimeMs {
                    let onID = midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs)
                    eventIDs.append(onID)

                    let offID = midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs)
                    eventIDs.append(offID)
                }

            case .slide(let fromNote, let toNote, let offTime):
                guard fromNote.fret >= 0, toNote.fret >= 0 else { continue }
                
                let startMidiNote = midiNote(from: fromNote.string, fret: fromNote.fret)
                let velocity = UInt8(fromNote.velocity)
                let noteOnTimeMs = playbackStartTimeMs + (fromNote.startTime * beatsToSeconds * 1000.0)
                let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                let onID = midiManager.scheduleNoteOn(note: startMidiNote, velocity: velocity, scheduledUptimeMs: noteOnTimeMs)
                eventIDs.append(onID)

                let slideStartTimeBeats = fromNote.startTime
                let slideEndTimeBeats = toNote.startTime
                let slideDurationBeats = slideEndTimeBeats - slideStartTimeBeats
                
                if slideDurationBeats > 0 {
                    let pitchBendSteps = max(2, Int(slideDurationBeats * beatsToSeconds * 50))
                    let fretDifference = toNote.fret - fromNote.fret
                    
                    let pitchBendRangeSemitones = 12.0
                    let finalPitchBendValue = 8192 + Int(Double(fretDifference) * (8191.0 / pitchBendRangeSemitones))

                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let intermediateTimeBeats = slideStartTimeBeats + (t * slideDurationBeats)
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        
                        let bendTimeMs = playbackStartTimeMs + (intermediateTimeBeats * beatsToSeconds * 1000.0)
                        let bendID = midiManager.schedulePitchBend(value: UInt16(intermediatePitch), scheduledUptimeMs: bendTimeMs)
                        eventIDs.append(bendID)
                    }
                }
                
                let offID = midiManager.scheduleNoteOff(note: startMidiNote, velocity: 0, scheduledUptimeMs: noteOffTimeMs)
                eventIDs.append(offID)
                
                let resetID = midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1)
                eventIDs.append(resetID)

            case .vibrato(let note, let offTime):
                guard note.fret >= 0 else { continue }
            
                let midiNoteNumber = midiNote(from: note.string, fret: note.fret)
                let velocity = UInt8(note.velocity)
                let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                let onID = midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs)
                eventIDs.append(onID)

                let vibratoStartTimeBeats = note.startTime
                let vibratoDurationBeats = offTime - vibratoStartTimeBeats

                if vibratoDurationBeats > 0.1 { // Only apply if note is long enough
                    let vibratoRateHz = 5.5
                    let vibratoIntensity = note.articulation?.vibratoIntensity ?? 0.5
                    
                    let maxBendSemitones = 0.4
                    let pitchBendRangeSemitones = 12.0
                    let maxPitchBendAmount = (maxBendSemitones / pitchBendRangeSemitones) * 8191.0 * vibratoIntensity

                    let vibratoDurationSeconds = vibratoDurationBeats * beatsToSeconds
                    let totalCycles = vibratoDurationSeconds * vibratoRateHz
                    let stepsPerCycle = 12.0
                    let totalSteps = Int(totalCycles * stepsPerCycle)

                    if totalSteps > 0 {
                        for step in 0...totalSteps {
                            let t_duration = Double(step) / Double(totalSteps)
                            let t_angle = t_duration * totalCycles * 2.0 * .pi
                            
                            let sineValue = sin(t_angle)
                            let pitchBendValue = 8192 + Int(sineValue * maxPitchBendAmount)

                            let bendTimeBeats = vibratoStartTimeBeats + (t_duration * vibratoDurationBeats)
                            let bendTimeMs = playbackStartTimeMs + (bendTimeBeats * beatsToSeconds * 1000.0)
                            
                            let bendID = midiManager.schedulePitchBend(value: UInt16(pitchBendValue), scheduledUptimeMs: bendTimeMs)
                            eventIDs.append(bendID)
                        }
                    }
                }

                let offID = midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs)
                eventIDs.append(offID)
                
                let resetID = midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1)
                eventIDs.append(resetID)
                
            case .bend(let note, let offTime):
                guard note.fret >= 0 else { continue }
                
                let midiNoteNumber = midiNote(from: note.string, fret: note.fret)
                let velocity = UInt8(note.velocity)
                let noteOnTimeMs = playbackStartTimeMs + (note.startTime * beatsToSeconds * 1000.0)
                let noteOffTimeMs = playbackStartTimeMs + (offTime * beatsToSeconds * 1000.0)

                let onID = midiManager.scheduleNoteOn(note: midiNoteNumber, velocity: velocity, scheduledUptimeMs: noteOnTimeMs)
                eventIDs.append(onID)

                let bendAmountSemitones = note.articulation?.bendAmount ?? 1.0
                if bendAmountSemitones > 0 {
                    let bendDurationSeconds = 0.1
                    let bendDurationBeats = bendDurationSeconds / beatsToSeconds
                    
                    let pitchBendRangeSemitones = 12.0
                    let finalPitchBendValue = 8192 + Int(bendAmountSemitones * (8191.0 / pitchBendRangeSemitones))
                    
                    let pitchBendSteps = 10

                    for step in 0...pitchBendSteps {
                        let t = Double(step) / Double(pitchBendSteps)
                        let intermediateTimeBeats = note.startTime + (t * bendDurationBeats)
                        let intermediatePitch = 8192 + Int(Double(finalPitchBendValue - 8192) * t)
                        
                        let bendTimeMs = playbackStartTimeMs + (intermediateTimeBeats * beatsToSeconds * 1000.0)
                        
                        if bendTimeMs < noteOffTimeMs {
                            let bendID = midiManager.schedulePitchBend(value: UInt16(intermediatePitch), scheduledUptimeMs: bendTimeMs)
                            eventIDs.append(bendID)
                        }
                    }
                }

                let offID = midiManager.scheduleNoteOff(note: midiNoteNumber, velocity: 0, scheduledUptimeMs: noteOffTimeMs)
                eventIDs.append(offID)
                
                let resetID = midiManager.schedulePitchBend(value: 8192, scheduledUptimeMs: noteOffTimeMs + 1)
                eventIDs.append(resetID)
            }
        }
        self.scheduledEventIDs = eventIDs

        // Start UI timer for playback line
        self.playbackStartDate = Date()
        self.uiTimerCancellable = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect().sink { _ in
            guard let startDate = self.playbackStartDate else { return }
            let elapsedSeconds = Date().timeIntervalSince(startDate)
            let beatsPerSecond = bpm / 60.0
            self.playbackPosition = elapsedSeconds * beatsPerSecond
            
            if self.playbackPosition > soloSegment.lengthInBeats {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        midiManager.cancelAllPendingScheduledEvents()
        midiManager.sendPitchBend(value: 8192)
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
                        Text(technique.chineseName).tag(technique)
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