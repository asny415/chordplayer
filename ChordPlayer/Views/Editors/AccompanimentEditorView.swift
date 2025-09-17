import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Editor View

struct AccompanimentEditorView: View {
    @Binding var segment: AccompanimentSegment
    let isNew: Bool
    let onSave: (AccompanimentSegment) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer

    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedEventId: UUID? // Can be either chord or pattern

    private var timeSignature: TimeSignature { appData.preset?.timeSignature ?? TimeSignature() }

    var body: some View {
        VStack(spacing: 0) {
            AccompanimentToolbar(
                segmentName: $segment.name,
                zoomLevel: $zoomLevel,
                onPlay: { chordPlayer.play(segment: segment) },
                onStop: { chordPlayer.panic() }
            )
            .padding()
            .background(Color.black.opacity(0.1))

            Divider()

            HSplitView {
                TimelineContainerView(
                    segment: $segment,
                    timeSignature: timeSignature,
                    zoomLevel: $zoomLevel,
                    selectedEventId: $selectedEventId
                )
                .frame(minWidth: 600)

                ResourceLibraryView()
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 450)
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
    @Binding var segmentName: String
    @Binding var zoomLevel: CGFloat
    let onPlay: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack {
            TextField("Segment Name", text: $segmentName).textFieldStyle(.plain).font(.title.weight(.semibold))
            Spacer()
            Button(action: onPlay) { Image(systemName: "play.fill") }
            Button(action: onStop) { Image(systemName: "stop.fill") }
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...4.0).frame(width: 100)
            }.help("Zoom")
        }
    }
}

// MARK: - Timeline UI
struct TimelineContainerView: View {
    @Binding var segment: AccompanimentSegment
    let timeSignature: TimeSignature
    @Binding var zoomLevel: CGFloat
    @Binding var selectedEventId: UUID?

    private let beatWidth: CGFloat = 60
    private let trackHeight: CGFloat = 50
    private let headerHeight: CGFloat = 25

    private var totalBeats: Int { segment.lengthInMeasures * timeSignature.beatsPerMeasure }
    private var totalWidth: CGFloat { CGFloat(totalBeats) * beatWidth * zoomLevel }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                TimelineGridView(totalBeats: totalBeats, beatsPerMeasure: timeSignature.beatsPerMeasure, beatWidth: beatWidth, height: trackHeight * 2 + headerHeight, zoom: zoomLevel)
                TimelineHeaderView(totalMeasures: segment.lengthInMeasures, beatsPerMeasure: timeSignature.beatsPerMeasure, beatWidth: beatWidth, height: headerHeight, zoom: zoomLevel)

                VStack(alignment: .leading, spacing: 0) {
                    TrackView(type: .chord, segment: $segment, timeSignature: timeSignature, height: trackHeight, beatWidth: beatWidth, zoom: zoomLevel, selectedEventId: $selectedEventId)
                    TrackView(type: .pattern, segment: $segment, timeSignature: timeSignature, height: trackHeight, beatWidth: beatWidth, zoom: zoomLevel, selectedEventId: $selectedEventId)
                }
                .padding(.top, headerHeight)
            }
            .frame(width: totalWidth)
        }
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
                        .onTapGesture { selectedEventId = event.id }
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
            
            Text(name).font(.caption).padding(.horizontal, 4).foregroundColor(.white)
        }
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

// MARK: - Resource Library & Buttons
struct ResourceLibraryView: View {
    @EnvironmentObject var appData: AppData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chords").font(.headline)
                    if let chords = appData.preset?.chords, !chords.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 75))], spacing: 8) {
                            ForEach(chords) { chord in
                                ResourceChordButton(chord: chord)
                                    .onDrag {
                                        let dragData = DragData(source: .newResource, type: .chord, resourceId: chord.id, eventId: nil, durationInBeats: 4)
                                        let provider = NSItemProvider()
                                        provider.registerCodable(dragData)
                                        return provider
                                    }
                            }
                        }
                    } else { Text("No chords in preset.").foregroundColor(.secondary) }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playing Patterns").font(.headline)
                    if let patterns = appData.preset?.playingPatterns, !patterns.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                            ForEach(patterns) { pattern in
                                ResourcePatternButton(pattern: pattern)
                                    .onDrag {
                                        let beats = pattern.length / (pattern.resolution == .sixteenth ? 4 : 2)
                                        let dragData = DragData(source: .newResource, type: .pattern, resourceId: pattern.id, eventId: nil, durationInBeats: beats > 0 ? beats : 1)
                                        let provider = NSItemProvider()
                                        provider.registerCodable(dragData)
                                        return provider
                                    }
                            }
                        }
                    } else { Text("No patterns in preset.").foregroundColor(.secondary) }
                }
            }.padding()
        }
    }
}


struct ResourceChordButton: View {
    let chord: Chord
    var body: some View {
        VStack(spacing: 2) {
            Text(chord.name).font(.caption).fontWeight(.semibold)
            ChordDiagramView(chord: chord, color: .primary).frame(height: 30)
        }.padding(4).frame(width: 80, height: 50).background(Material.thin, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ResourcePatternButton: View {
    let pattern: GuitarPattern
    var body: some View {
        VStack(spacing: 2) {
            Text(pattern.name).font(.caption).fontWeight(.semibold)
            Text("\(pattern.length / (pattern.resolution == .sixteenth ? 4 : 2)) beats").font(.caption2).foregroundColor(.secondary)
        }.padding(4).frame(width: 120, height: 40).background(Material.thin, in: RoundedRectangle(cornerRadius: 6))
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
                
                // Step 2: Create the new event instance to be placed
                let newEvent = TimelineEvent(
                    id: eventToDropId,
                    resourceId: dragData.resourceId,
                    startBeat: startBeatInMeasure,
                    durationInBeats: dragData.durationInBeats
                )

                // Step 3: Add the new event to the target location
                if self.trackType == .chord {
                    // Prevent overlap
                    if !updatedSegment.measures[measureIndex].chordEvents.contains(where: { $0.startBeat == newEvent.startBeat }) {
                        updatedSegment.measures[measureIndex].chordEvents.append(newEvent)
                    }
                } else {
                    // Prevent overlap
                    if !updatedSegment.measures[measureIndex].patternEvents.contains(where: { $0.startBeat == newEvent.startBeat }) {
                        updatedSegment.measures[measureIndex].patternEvents.append(newEvent)
                    }
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
                               with: .color(isMeasureLine ? .primary.opacity(0.5) : .secondary.opacity(0.3)), 
                               lineWidth: isMeasureLine ? 1.0 : 0.5)
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

