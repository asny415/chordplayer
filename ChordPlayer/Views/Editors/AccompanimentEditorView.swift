import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Editor View

struct AccompanimentEditorView: View {
    enum Field { case segmentName }
    @FocusState private var focusedField: Field?

    @Binding var segment: AccompanimentSegment
    let isNew: Bool
    let onSave: (AccompanimentSegment) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer

    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedEventId: UUID? // Can be either chord or pattern
    @State private var selectedChordId: UUID? // Track the currently selected chord resource ID
    @State private var isPlaying: Bool = false
    @State private var playbackEndTask: DispatchWorkItem?
    @State private var playbackStartTime: TimeInterval? = nil
    @State private var isShowingChordCreator = false
    @State private var isShowingPatternEditor = false
    
    @State private var newChordForEditing = Chord(name: "New Chord", frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0])
    @State private var newPatternForEditing = GuitarPattern.createNew(name: "New Pattern", length: 8, resolution: .sixteenth)
    
    @State private var showInUseAlert = false
    @State private var inUseAlertMessage = ""


    private var timeSignature: TimeSignature { appData.preset?.timeSignature ?? TimeSignature() }

    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack {
                if isEditingName {
                    TextField("Segment Name", text: $segment.name)
                        .font(.largeTitle)
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .onSubmit { isEditingName = false }
                        .onDisappear { isEditingName = false } // Ensure editing stops if view disappears
                } else {
                    Text(segment.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .onTapGesture(count: 2) {
                            isEditingName = true
                            isNameFieldFocused = true
                        }
                }
                AccompanimentToolbar(
                    zoomLevel: $zoomLevel,
                    isPlaying: $isPlaying,
                    measureCount: segment.lengthInMeasures,
                    onTogglePlayback: {
                        if isPlaying {
                            stop()
                        } else {
                            play()
                        }
                    },
                    onAddMeasure: addMeasure,
                    onRemoveMeasure: removeMeasure
                )
            }
            .padding()
            .background(Color.black.opacity(0.1))

            Divider()

            HSplitView {
                // Main content: Libraries on top, timeline on bottom with a draggable splitter
                VSplitView {
                    ResourceLibraryView(
                        segment: $segment,
                        selectedEventId: $selectedEventId,
                        isShowingChordCreator: $isShowingChordCreator,
                        isShowingPatternEditor: $isShowingPatternEditor,
                        onDeleteChord: deleteChord,
                        onDeletePattern: deletePattern
                    )
                    TimelineContainerView(
                        segment: $segment,
                        timeSignature: timeSignature,
                        zoomLevel: $zoomLevel,
                        selectedEventId: $selectedEventId,
                        playbackStartTime: playbackStartTime
                    ).frame(height:160)
                }
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    focusedField = nil
                    selectedEventId = nil
                }

                // Inspector panel on the right
                SidePanelView(
                    segment: $segment,
                    selectedEventId: $selectedEventId,
                    onUpdateEventDuration: updateEventDuration
                )
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Save", action: { onSave(segment) }).keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 1000, idealWidth: 1400, minHeight: 600, idealHeight: 800)
        .background(Color(NSColor.windowBackgroundColor))
        .background(
            Button("", action: deleteSelectedEvent)
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
        )
        .sheet(isPresented: $isShowingChordCreator) {
            ChordEditorView(
                chord: $newChordForEditing,
                isNew: true,
                onSave: { savedChord in
                    appData.preset?.chords.append(savedChord)
                    appData.saveChanges()
                    isShowingChordCreator = false
                    // Reset for next time
                    newChordForEditing = Chord(name: "New Chord", frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0])
                },
                onCancel: {
                    isShowingChordCreator = false
                    // Reset for next time
                    newChordForEditing = Chord(name: "New Chord", frets: [-1, -1, -1, -1, -1, -1], fingers: [0, 0, 0, 0, 0, 0])
                }
            )
        }
        .sheet(isPresented: $isShowingPatternEditor) {
            PlayingPatternEditorView(
                pattern: $newPatternForEditing,
                isNew: true,
                onSave: { newPattern in
                    var patternToSave = newPattern
                    if patternToSave.name == "New Pattern" {
                        patternToSave.name = patternToSave.generateAutomaticName()
                    }
                    appData.preset?.playingPatterns.append(patternToSave)
                    appData.saveChanges()
                    isShowingPatternEditor = false
                    // Reset for next time
                    newPatternForEditing = GuitarPattern.createNew(name: "New Pattern", length: 8, resolution: .sixteenth)
                },
                onCancel: {
                    isShowingPatternEditor = false
                    // Reset for next time
                    newPatternForEditing = GuitarPattern.createNew(name: "New Pattern", length: 8, resolution: .sixteenth)
                }
            )
        }
        .alert("Cannot Delete", isPresented: $showInUseAlert) {
            Button("OK") { }
        } message: {
            Text(inUseAlertMessage)
        }
    }

    private func deleteSelectedEvent() {
        guard let selectedId = selectedEventId else { return }

        var updatedSegment = segment
        var eventFoundAndRemoved = false

        for i in 0..<updatedSegment.measures.count {
            if let index = updatedSegment.measures[i].chordEvents.firstIndex(where: { $0.id == selectedId }) {
                updatedSegment.measures[i].chordEvents.remove(at: index)
                eventFoundAndRemoved = true
                break
            }
            if let index = updatedSegment.measures[i].patternEvents.firstIndex(where: { $0.id == selectedId }) {
                updatedSegment.measures[i].patternEvents.remove(at: index)
                eventFoundAndRemoved = true
                break
            }
        }

        if eventFoundAndRemoved {
            segment = updatedSegment
            selectedEventId = nil
        }
    }

    private func play() {
        // Cancel any previously scheduled stop task
        playbackEndTask?.cancel()

        guard let preset = appData.preset else { return }
        
        // Reset playhead and start playback
        playbackStartTime = ProcessInfo.processInfo.systemUptime
        chordPlayer.play(segment: segment)
        isPlaying = true

        // Schedule a task to set isPlaying to false when playback finishes
        let durationInSeconds = Double(segment.lengthInMeasures * preset.timeSignature.beatsPerMeasure) * (60.0 / preset.bpm)
        
        let task = DispatchWorkItem(block: {
            // Check if we are still in a playing state before automatically stopping
            if self.isPlaying {
                self.isPlaying = false
                self.playbackStartTime = nil
            }
        })
        playbackEndTask = task
        
        // Add a small buffer to ensure sounds can finish
        DispatchQueue.main.asyncAfter(deadline: .now() + durationInSeconds + 0.2, execute: task)
    }

    private func stop() {
        // Cancel the scheduled stop task
        playbackEndTask?.cancel()
        
        // Stop all sounds and reset state
        chordPlayer.stop()
        isPlaying = false
        playbackStartTime = nil
    }

    private func updateEventDuration(eventId: UUID, newDuration: Int) {
        guard newDuration >= 1 else { return }
        var updatedSegment = segment
        
        for i in 0..<updatedSegment.measures.count {
            if let index = updatedSegment.measures[i].chordEvents.firstIndex(where: { $0.id == eventId }) {
                updatedSegment.measures[i].chordEvents[index].durationInBeats = newDuration
                segment = updatedSegment
                return
            }
            if let index = updatedSegment.measures[i].patternEvents.firstIndex(where: { $0.id == eventId }) {
                updatedSegment.measures[i].patternEvents[index].durationInBeats = newDuration
                segment = updatedSegment
                return
            }
        }
    }

    private func addMeasure() {
        var updatedSegment = segment
        updatedSegment.updateLength(updatedSegment.lengthInMeasures + 1)
        segment = updatedSegment
    }

    private func removeMeasure() {
        guard segment.lengthInMeasures > 1 else { return }
        var updatedSegment = segment
        updatedSegment.updateLength(updatedSegment.lengthInMeasures - 1)
        segment = updatedSegment
    }
    
    private func deleteChord(withId chordId: UUID) {
        let isChordInUse = appData.preset?.accompanimentSegments.contains { segment in
            segment.measures.contains { measure in
                measure.chordEvents.contains { $0.resourceId == chordId }
            }
        } ?? false

        if isChordInUse {
            inUseAlertMessage = "This chord is used in at least one accompaniment segment. Please remove it from all segments before deleting."
            showInUseAlert = true
        } else {
            appData.preset?.chords.removeAll { $0.id == chordId }
            appData.saveChanges()
        }
    }

    private func deletePattern(withId patternId: UUID) {
        let isPatternInUse = appData.preset?.accompanimentSegments.contains { segment in
            segment.measures.contains { measure in
                measure.patternEvents.contains { $0.resourceId == patternId }
            }
        } ?? false

        if isPatternInUse {
            inUseAlertMessage = "This pattern is used in at least one accompaniment segment. Please remove it from all segments before deleting."
            showInUseAlert = true
        } else {
            appData.preset?.playingPatterns.removeAll { $0.id == patternId }
            appData.saveChanges()
        }
    }
}

enum DragSource: String, Codable { case newResource, existingEvent }

// MARK: - Drag & Drop Data
enum EventType: String, Codable { case chord, pattern }
struct DragData: Codable {
    let source: DragSource
    let type: EventType // chord or pattern
    let resourceId: UUID // For newResource, chord/pattern ID. For existingEvent, also the chord/pattern ID.
    let eventId: UUID?   // For existingEvent, the ID of the event being moved.
    let durationInBeats: Int
    
    static let typeIdentifier = "public.data"
}

// MARK: - Toolbar
struct AccompanimentToolbar: View {
    @Binding var zoomLevel: CGFloat
    @Binding var isPlaying: Bool
    let measureCount: Int
    let onTogglePlayback: () -> Void
    let onAddMeasure: () -> Void
    let onRemoveMeasure: () -> Void

    var body: some View {
        HStack {
            Text("\(measureCount) Measures").font(.callout).foregroundColor(.secondary)
            Button(action: onRemoveMeasure) {
                Image(systemName: "minus.square")
            }.disabled(measureCount <= 1)
            Button(action: onAddMeasure) {
                Image(systemName: "plus.square")
            }
            
            Spacer()
            
            Button(action: onTogglePlayback) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
            }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...4.0).frame(width: 100)
            }.help("Zoom")
        }
    }
}

// MARK: - Timeline UI

private struct EditorPlayheadView: View {
    let position: CGFloat
    let height: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2)
            .offset(x: position - 1) // Center the 2pt line on the position
            .frame(height: height)
    }
}



struct TrackHeadersView: View {
    let trackHeight: CGFloat
    let headerHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // Spacer to align with the timeline's measure number header
            Rectangle()
                .fill(Color(NSColor.windowBackgroundColor))
                .frame(height: headerHeight)
                .border(Color.secondary.opacity(0.5), width: 0.5)

            // Header for Chord Track
            ZStack {
                Rectangle().fill(Color.blue.opacity(0.05))
                Text("Chords")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(height: trackHeight)
            .border(Color.secondary.opacity(0.5), width: 0.5)

            // Header for Pattern Track
            ZStack {
                Rectangle().fill(Color.green.opacity(0.05))
                Text("Patterns")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .frame(height: trackHeight)
            .border(Color.secondary.opacity(0.5), width: 0.5)
        }
        .frame(width: 90)
    }
}

struct TimelineContainerView: View {
    @Binding var segment: AccompanimentSegment
    let timeSignature: TimeSignature
    @Binding var zoomLevel: CGFloat
    @Binding var selectedEventId: UUID?
    let playbackStartTime: TimeInterval?
    
    @EnvironmentObject var appData: AppData

    private let beatWidth: CGFloat = 60
    private let trackHeight: CGFloat = 60
    private let headerHeight: CGFloat = 25

    private var totalBeats: Int { segment.lengthInMeasures * timeSignature.beatsPerMeasure }
    private var totalWidth: CGFloat { CGFloat(totalBeats) * beatWidth * zoomLevel }
    private var secondsPerBeat: Double { 60.0 / (appData.preset?.bpm ?? 120.0) }

    var body: some View {
        TimelineView(.animation) { context in
            let playheadInBeats = calculatePlayheadPosition(context: context)
            
            HStack(spacing: 0) {
                TrackHeadersView(trackHeight: trackHeight, headerHeight: headerHeight)
                
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        TimelineGridView(totalBeats: totalBeats, beatsPerMeasure: timeSignature.beatsPerMeasure, beatWidth: beatWidth, height: trackHeight * 2 + headerHeight, zoom: zoomLevel)
                        TimelineHeaderView(totalMeasures: segment.lengthInMeasures, beatsPerMeasure: timeSignature.beatsPerMeasure, beatWidth: beatWidth, height: headerHeight, zoom: zoomLevel)

                        VStack(alignment: .leading, spacing: 0) {
                            TrackView(type: .chord, segment: $segment, timeSignature: timeSignature, height: trackHeight, beatWidth: beatWidth, zoom: zoomLevel, selectedEventId: $selectedEventId)
                            TrackView(type: .pattern, segment: $segment, timeSignature: timeSignature, height: trackHeight, beatWidth: beatWidth, zoom: zoomLevel, selectedEventId: $selectedEventId)
                        }
                        .padding(.top, headerHeight)
                        
                        if let playheadInBeats = playheadInBeats {
                            EditorPlayheadView(
                                position: CGFloat(playheadInBeats) * beatWidth * zoomLevel,
                                height: trackHeight * 2 + headerHeight
                            )
                        }
                    }
                    .frame(width: totalWidth)
                }
            }
        }
    }
    
    private func calculatePlayheadPosition(context: TimelineViewDefaultContext) -> Double? {
        guard let playbackStartTime = playbackStartTime else { return nil }
        
        let now = ProcessInfo.processInfo.systemUptime
        let elapsedTime = now - playbackStartTime
        let currentBeat = elapsedTime / secondsPerBeat
        
        if currentBeat > Double(totalBeats) {
            return nil
        }
        return currentBeat
    }
}

struct TrackView: View {
    let type: EventType
    @Binding var segment: AccompanimentSegment
    let timeSignature: TimeSignature
    let height: CGFloat
    let beatWidth: CGFloat
    let zoom: CGFloat
    @Binding var selectedEventId: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(type == .chord ? Color.blue.opacity(0.05) : Color.green.opacity(0.05))
            
            ForEach(0..<segment.measures.count, id: \.self) { measureIndex in
                let measureStartBeat = measureIndex * timeSignature.beatsPerMeasure
                let events = (type == .chord) ? segment.measures[measureIndex].chordEvents : segment.measures[measureIndex].patternEvents
                
                ForEach(events) { event in
                    TimelineEventView(event: event, type: type, isSelected: selectedEventId == event.id)
                        .frame(width: CGFloat(event.durationInBeats) * beatWidth * zoom)
                        .offset(x: (CGFloat(measureStartBeat) + CGFloat(event.startBeat)) * beatWidth * zoom)
                        .onTapGesture {
                            selectedEventId = event.id
                        }
                }
            }
        }
        .frame(height: height)
        .onDrop(of: [DragData.typeIdentifier], delegate: DropHandler(segment: $segment, selectedEventId: $selectedEventId, trackType: type, timeSignature: timeSignature, beatWidth: beatWidth, zoom: zoom))
    }
}

struct TimelineEventView: View {
    let event: TimelineEvent
    let type: EventType
    let isSelected: Bool
    @EnvironmentObject var appData: AppData

    private var name: String {
        guard let preset = appData.preset else { return "?" }
        if type == .chord {
            return preset.chords.first { $0.id == event.resourceId }?.name ?? "Err"
        } else {
            return preset.playingPatterns.first { $0.id == event.resourceId }?.name ?? "Err"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill( (type == .chord ? Color.blue : Color.green).opacity(isSelected ? 0.8 : 0.4) )
                .border(Color.black.opacity(0.5), width: 0.5)
            
            if isSelected {
                RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 2)
            }
            
            if type == .chord, let chord = appData.preset?.chords.first(where: { $0.id == event.resourceId }) {
                GeometryReader { geometry in
                    if geometry.size.width > 35 {
                        VStack {
                            Text(name).font(.callout).fontWeight(.semibold)
                            ChordDiagramView(chord: chord, color: .white.opacity(0.8))
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                Text(name).font(.caption).padding(.horizontal, 4)
            }
        }
        .foregroundColor(.white)
        .onDrag {
            let dragData = DragData(
                source: .existingEvent,
                type: self.type,
                resourceId: event.resourceId,
                eventId: event.id,
                durationInBeats: event.durationInBeats
            )
            let provider = NSItemProvider()
            provider.registerCodable(dragData)
            return provider
        }
    }
}

// MARK: - Inspector and Side Panel

struct InspectorView: View {
    @Binding var segment: AccompanimentSegment
    let selectedEventId: UUID
    let onUpdateDuration: (Int) -> Void
    
    // Find the event and its type
    private var eventInfo: (event: TimelineEvent, type: EventType)? {
        for measure in segment.measures {
            if let event = measure.chordEvents.first(where: { $0.id == selectedEventId }) {
                return (event, .chord)
            }
            if let event = measure.patternEvents.first(where: { $0.id == selectedEventId }) {
                return (event, .pattern)
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let info = eventInfo {
                Text("Inspector").font(.title2)
                Text("Event ID: \(info.event.id.uuidString.prefix(8))")
                Text("Type: \(info.type.rawValue)")
                
                Divider()
                
                VStack(alignment: .leading) {
                    Text("Start Beat").font(.headline)
                    Text("\(info.event.startBeat)")
                }
                
                VStack(alignment: .leading) {
                    Text("Duration (beats)").font(.headline)
                    Stepper("\(info.event.durationInBeats)",
                            onIncrement: { onUpdateDuration(info.event.durationInBeats + 1) },
                            onDecrement: { onUpdateDuration(info.event.durationInBeats - 1) })
                }

                Spacer()
            } else {
                Text("No event selected or found.")
            }
        }
        .padding()
    }
}

struct SidePanelView: View {
    @Binding var segment: AccompanimentSegment
    @Binding var selectedEventId: UUID?
    let onUpdateEventDuration: (UUID, Int) -> Void
    
    var body: some View {
        VStack {
            if let eventId = selectedEventId {
                InspectorView(
                    segment: $segment,
                    selectedEventId: eventId,
                    onUpdateDuration: { newDuration in
                        onUpdateEventDuration(eventId, newDuration)
                    }
                )
            } else {
                VStack {
                    Spacer()
                    Text("Select an event on the timeline to see its properties.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            }
        }
        .frame(width: 200)
    }
}


// MARK: - Resource Library & Buttons
struct ResourceLibraryView: View {
    @EnvironmentObject var appData: AppData
    @Binding var segment: AccompanimentSegment
    @Binding var selectedEventId: UUID?
    @Binding var isShowingChordCreator: Bool
    @Binding var isShowingPatternEditor: Bool
    let onDeleteChord: (UUID) -> Void
    let onDeletePattern: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Chord Library
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Chords").font(.headline)
                    Spacer()
                    Button(action: { isShowingChordCreator = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    if let chords = appData.preset?.chords, !chords.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                            ForEach(chords) { chord in
                                ResourceChordButton(chord: chord, isSelected: isSelectedChord(chord.id), onDelete: { onDeleteChord(chord.id) })
                                    .onDrag {
                                        let dragData = DragData(source: .newResource, type: .chord, resourceId: chord.id, eventId: nil, durationInBeats: 1)
                                        let provider = NSItemProvider()
                                        provider.registerCodable(dragData)
                                        return provider
                                    }
                            }
                        }
                    } else { Text("No chords in preset.").foregroundColor(.secondary).padding() }
                }.background(Color.black.opacity(0.1))
            }
            
            // Pattern Library
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Playing Patterns").font(.headline)
                    Spacer()
                    Button(action: { isShowingPatternEditor = true }) {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    if let patterns = appData.preset?.playingPatterns, !patterns.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                            ForEach(patterns) { pattern in
                                ResourcePatternButton(pattern: pattern, isSelected: isSelectedPattern(pattern.id), onDelete: { onDeletePattern(pattern.id) })
                                    .onDrag {
                                        let beats = pattern.length / (pattern.resolution == .sixteenth ? 4 : 2)
                                        let dragData = DragData(source: .newResource, type: .pattern, resourceId: pattern.id, eventId: nil, durationInBeats: beats > 0 ? beats : 1)
                                        let provider = NSItemProvider()
                                        provider.registerCodable(dragData)
                                        return provider
                                    }
                            }
                        }
                    } else { Text("No patterns in preset.").foregroundColor(.secondary).padding() }
                }.background(Color.black.opacity(0.1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private func isSelectedChord(_ chordId: UUID) -> Bool {
        guard let selectedId = selectedEventId else { return false }
        
        // Find the selected event and check if it's a chord event with the specified chord ID
        for measure in segment.measures {
            if let chordEvent = measure.chordEvents.first(where: { $0.id == selectedId }) {
                return chordEvent.resourceId == chordId
            }
        }
        
        // If the selected event is not a chord event, find the chord associated with the selected pattern event
        for measure in segment.measures {
            if let patternEvent = measure.patternEvents.first(where: { $0.id == selectedId }) {
                // Find the chord at the same position or before it
                let chordIdAtPosition = getChordIdAtPosition(measureIndex: segment.measures.firstIndex(of: measure)!, startBeat: patternEvent.startBeat)
                return chordIdAtPosition == chordId
            }
        }
        
        return false
    }
    
    private func isSelectedPattern(_ patternId: UUID) -> Bool {
        // First, determine which chord type should be considered as "selected"
        var chordType: UUID?
        
        if let selectedId = selectedEventId {
            // Check if a chord event is selected directly
            for measure in segment.measures {
                if let chordEvent = measure.chordEvents.first(where: { $0.id == selectedId }) {
                    chordType = chordEvent.resourceId
                    break
                }
            }
            
            // If no chord event is selected, check if a pattern event is selected
            if chordType == nil {
                for measure in segment.measures {
                    if let patternEvent = measure.patternEvents.first(where: { $0.id == selectedId }) {
                        // Find the chord at the same position or before it
                        chordType = getChordIdAtPosition(measureIndex: segment.measures.firstIndex(of: measure)!, startBeat: patternEvent.startBeat)
                        break
                    }
                }
            }
        }
        
        // If no chord type could be determined, return false
        guard let selectedChordType = chordType else {
            return false
        }
        
        // Now find all positions where this chord type is effective
        // Create a timeline of chord changes
        let beatsPerMeasure = appData.preset?.timeSignature.beatsPerMeasure ?? 4
        var chordTimeline: [(startPos: Int, endPos: Int, chordId: UUID)] = []
        var allChordEvents: [(absolutePosition: Int, event: TimelineEvent)] = []
        
        // Collect all chord events
        for (measureIdx, measure) in segment.measures.enumerated() {
            for chordEvent in measure.chordEvents {
                let absolutePosition = measureIdx * beatsPerMeasure + chordEvent.startBeat
                allChordEvents.append((absolutePosition: absolutePosition, event: chordEvent))
            }
        }
        
        // Sort chord events by position
        allChordEvents.sort { $0.absolutePosition < $1.absolutePosition }
        
        // Create timeline segments for each chord
        for i in 0..<allChordEvents.count {
            let currentEvent = allChordEvents[i]
            let startPos = currentEvent.absolutePosition
            
            var endPos: Int
            if i == allChordEvents.count - 1 {
                // Last chord event - continues to end of segment
                endPos = segment.measures.count * beatsPerMeasure
            } else {
                // Until the next chord event
                endPos = allChordEvents[i + 1].absolutePosition
            }
            
            chordTimeline.append((startPos: startPos, endPos: endPos, chordId: currentEvent.event.resourceId))
        }
        
        // Find all pattern events that occur during any occurrence of the selected chord type
        for (measureIdx, measure) in segment.measures.enumerated() {
            for patternEvent in measure.patternEvents {
                if patternEvent.resourceId == patternId {
                    let patternPos = measureIdx * beatsPerMeasure + patternEvent.startBeat
                    
                    // Check if this pattern position falls within any segment of the selected chord type
                    for timelineSegment in chordTimeline {
                        if timelineSegment.chordId == selectedChordType && 
                           patternPos >= timelineSegment.startPos && 
                           patternPos < timelineSegment.endPos {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    private func getChordIdAtPosition(measureIndex: Int, startBeat: Int) -> UUID? {
        
        // Go through all measures up to and including the target measure
        var lastChordSoFar: UUID? = nil
        
        for i in 0...measureIndex {
            let measure = segment.measures[i]
            let chordsInMeasure = measure.chordEvents.sorted { $0.startBeat < $1.startBeat }
            
            if i == measureIndex {
                // In the target measure, look for chords at or before the startBeat
                for chord in chordsInMeasure {
                    if chord.startBeat <= startBeat {
                        lastChordSoFar = chord.resourceId
                    } else {
                        // If we find a chord after our target beat, we stop here
                        break
                    }
                }
            } else {
                // In previous measures, get the last chord by position
                if !chordsInMeasure.isEmpty {
                    if let lastChordInMeasure = chordsInMeasure.last {
                        lastChordSoFar = lastChordInMeasure.resourceId
                    }
                }
            }
        }
        
        return lastChordSoFar
    }
}


struct ResourceChordButton: View {
    let chord: Chord
    let isSelected: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            Text(chord.name).font(.caption).fontWeight(.semibold)
            ChordDiagramView(chord: chord, color: .primary)
        }
        .padding(4)
        .frame(width: 60, height: 70)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.yellow.opacity(0.3) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: isSelected ? 2 : 0)
                )
        )
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct ResourcePatternButton: View {
    let pattern: GuitarPattern
    let isSelected: Bool
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            Text(pattern.name).font(.caption).fontWeight(.semibold)
            PlayingPatternView(pattern: pattern, color: .primary)
                .frame(height: 30)
        }
        .padding(4)
        .frame(width: 120, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.yellow.opacity(0.3) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: isSelected ? 2 : 0)
                )
        )
        .help(pattern.name)
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Drop Handling & Grid Drawing

struct DropHandler: DropDelegate {
    @Binding var segment: AccompanimentSegment
    @Binding var selectedEventId: UUID?
    let trackType: EventType
    let timeSignature: TimeSignature
    let beatWidth: CGFloat
    let zoom: CGFloat

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [DragData.typeIdentifier]).first else { return false }
        
        _ = provider.loadDataRepresentation(forTypeIdentifier: DragData.typeIdentifier) { data, error in
            guard let data = data, let dragData = try? JSONDecoder().decode(DragData.self, from: data) else { return }
            
            // A drop is only valid on its own track type
            guard dragData.type == self.trackType else { return }

            DispatchQueue.main.async {
                let dropLocationX = info.location.x
                let beat = Int(floor(dropLocationX / (beatWidth * zoom)))
                let measureIndex = beat / timeSignature.beatsPerMeasure
                let startBeatInMeasure = beat % timeSignature.beatsPerMeasure
                
                guard segment.measures.indices.contains(measureIndex) else { return }
                
                var updatedSegment = segment
                let eventToDropId = UUID()

                // Step 1: Remove the original event if this is a move operation
                if dragData.source == .existingEvent, let existingEventId = dragData.eventId {
                    for i in 0..<updatedSegment.measures.count {
                        updatedSegment.measures[i].chordEvents.removeAll(where: { $0.id == existingEventId })
                        updatedSegment.measures[i].patternEvents.removeAll(where: { $0.id == existingEventId })
                    }
                }
                
                // Smart copy logic for chord drops at the beginning of a measure
                if self.trackType == .chord && startBeatInMeasure == 0 {
                    // Find the closest previous measure that starts with the same chord by searching backwards.
                    var sourceMeasureToCopy: AccompanimentMeasure? = nil
                    for i in (0..<measureIndex).reversed() {
                        let potentialSourceMeasure = updatedSegment.measures[i]
                        if let firstChordEvent = potentialSourceMeasure.chordEvents.first(where: { $0.startBeat == 0 }),
                           firstChordEvent.resourceId == dragData.resourceId {
                            sourceMeasureToCopy = potentialSourceMeasure
                            break // Found the closest match, use it
                        }
                    }
                    
                    // If a source measure was found, copy its entire contents
                    if let sourceMeasure = sourceMeasureToCopy {
                        // Clear existing events in the target measure before copying
                        updatedSegment.measures[measureIndex].patternEvents.removeAll()
                        updatedSegment.measures[measureIndex].chordEvents.removeAll()

                        // Copy pattern events from the source measure
                        for patternEventToCopy in sourceMeasure.patternEvents {
                            let newPatternEvent = TimelineEvent(
                                id: UUID(), // new unique ID
                                resourceId: patternEventToCopy.resourceId,
                                startBeat: patternEventToCopy.startBeat,
                                durationInBeats: patternEventToCopy.durationInBeats
                            )
                            updatedSegment.measures[measureIndex].patternEvents.append(newPatternEvent)
                        }
                        
                        // Copy chord events from the source measure
                        for chordEventToCopy in sourceMeasure.chordEvents {
                            let newChordEvent = TimelineEvent(
                                id: UUID(), // new unique ID
                                resourceId: chordEventToCopy.resourceId,
                                startBeat: chordEventToCopy.startBeat,
                                durationInBeats: chordEventToCopy.durationInBeats
                            )
                            updatedSegment.measures[measureIndex].chordEvents.append(newChordEvent)
                        }
                    }
                }

                // Step 2: Create the new event instance to be placed
                let newEvent = TimelineEvent(
                    id: eventToDropId,
                    resourceId: dragData.resourceId,
                    startBeat: startBeatInMeasure,
                    durationInBeats: dragData.durationInBeats
                )

                // Step 3: Add the new event to the target location
                if self.trackType == .chord {
                    // Prevent overlap by removing any existing chord at the exact same start beat
                    updatedSegment.measures[measureIndex].chordEvents.removeAll(where: { $0.startBeat == newEvent.startBeat })
                    updatedSegment.measures[measureIndex].chordEvents.append(newEvent)

                } else { // .pattern
                    // Prevent overlap by removing any existing pattern at the exact same start beat
                    updatedSegment.measures[measureIndex].patternEvents.removeAll(where: { $0.startBeat == newEvent.startBeat })
                    updatedSegment.measures[measureIndex].patternEvents.append(newEvent)
                }
                
                // Step 4: Assign back to binding and update selection
                if segment != updatedSegment {
                    segment = updatedSegment
                    selectedEventId = eventToDropId
                }
            }
        }
        return true
    }
}

struct TimelineGridView: View {
    let totalBeats: Int, beatsPerMeasure: Int, beatWidth: CGFloat, height: CGFloat, zoom: CGFloat
    var body: some View {
        Canvas { context, size in
            for beat in 0...totalBeats {
                let x = CGFloat(beat) * beatWidth * zoom
                let isMeasureLine = beat % beatsPerMeasure == 0
                context.stroke(Path { $0.move(to: .init(x: x, y: 0)); $0.addLine(to: .init(x: x, y: height)) }, 
                               with: .color(isMeasureLine ? .primary.opacity(0.6) : .secondary.opacity(0.4)), 
                               lineWidth: isMeasureLine ? 1.5 : 0.5)
            }
        }
    }
}

struct TimelineHeaderView: View {
    let totalMeasures: Int, beatsPerMeasure: Int, beatWidth: CGFloat, height: CGFloat, zoom: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalMeasures, id: \.self) { i in
                Text("\(i + 1)").font(.caption).foregroundColor(.secondary)
                    .frame(width: CGFloat(beatsPerMeasure) * beatWidth * zoom, height: height)
                    .background(i % 2 == 0 ? Color.black.opacity(0.1) : Color.clear)
                    .border(Color.secondary, width: 0.5)
            }
        }
    }
}

// A helper for making a type draggable using Codable
extension NSItemProvider {
    func registerCodable<T: Codable>(_ object: T) {
        do {
            let data = try JSONEncoder().encode(object)
            self.registerDataRepresentation(forTypeIdentifier: DragData.typeIdentifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        } catch {
            print("Failed to encode codable for drag and drop: \(error)")
        }
    }
}

