import SwiftUI

struct AccompanimentSegmentsView: View {
    @EnvironmentObject var appData: AppData

    @State private var segmentToEdit: AccompanimentSegment?

    var body: some View {
        VStack(alignment: .leading) {
            if let preset = appData.preset, !preset.accompanimentSegments.isEmpty {
                HStack {
                    Text("Accompaniment Segments").font(.headline)
                    Spacer()
                    Button(action: {
                        let newSegment = AccompanimentSegment(name: "New Accompaniment", lengthInMeasures: 4)
                        self.segmentToEdit = newSegment
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new accompaniment segment")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                    ForEach(preset.accompanimentSegments) { segment in
                        let isActive = appData.preset?.activeAccompanimentSegmentId == segment.id
                        
                        SegmentCardView(
                            title: segment.name,
                            systemImageName: "guitars",
                            isSelected: isActive
                        ) {
                            AccompanimentCardContent(segment: segment, preset: preset)
                        }
                        .onTapGesture(count: 2) {
                            self.segmentToEdit = segment
                        }
                        .onTapGesture {
                            appData.preset?.activeAccompanimentSegmentId = isActive ? nil : segment.id
                            appData.saveChanges()
                        }
                        .contextMenu {
                            contextMenuFor(segment: segment)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    imageName: "guitars",
                    text: "Create an Accompaniment",
                    action: {
                        let newSegment = AccompanimentSegment(name: "New Accompaniment", lengthInMeasures: 4)
                        self.segmentToEdit = newSegment
                    }
                )
            }
        }
        .sheet(item: $segmentToEdit) { segment in
            let isNew = !(appData.preset?.accompanimentSegments.contains(where: { $0.id == segment.id }) ?? false)
            
            EditorWrapperView(
                segmentToEdit: segment,
                isNew: isNew,
                onSave: { savedSegment in
                    if let index = appData.preset?.accompanimentSegments.firstIndex(where: { $0.id == savedSegment.id }) {
                        appData.preset?.accompanimentSegments[index] = savedSegment
                    } else {
                        appData.addAccompanimentSegment(savedSegment)
                    }
                    appData.saveChanges()
                    self.segmentToEdit = nil
                },
                onCancel: {
                    self.segmentToEdit = nil
                }
            )
            .environmentObject(appData)
        }
    }
    
    @ViewBuilder
    private func contextMenuFor(segment: AccompanimentSegment) -> some View {
        if let preset = appData.preset {
            let guitarTracks = preset.arrangement.guitarTracks
            if !guitarTracks.isEmpty {
                Menu("Add to Arrangement") {
                    ForEach(guitarTracks) { track in
                        Button("\(track.name)") {
                            addToGuitarTrack(accompanimentSegment: segment, trackId: track.id)
                        }
                    }
                }
                Divider()
            }
        }
        
        Button("Edit") {
            self.segmentToEdit = segment
        }
        Button("Duplicate") {
            var duplicatedSegment = segment
            duplicatedSegment.id = UUID()
            duplicatedSegment.name = "\(segment.name) Copy"
            appData.addAccompanimentSegment(duplicatedSegment)
        }
        Button("Delete", role: .destructive) {
            if let index = appData.preset?.accompanimentSegments.firstIndex(where: { $0.id == segment.id }) {
                appData.removeAccompanimentSegment(at: IndexSet(integer: index))
            }
        }
    }

    private func addToGuitarTrack(accompanimentSegment: AccompanimentSegment, trackId: UUID) {
        guard let preset = appData.preset,
              let trackIndex = preset.arrangement.guitarTracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        let track = preset.arrangement.guitarTracks[trackIndex]
        
        // Calculate the end beat of the last segment on this track
        let lastBeat = track.segments.map { $0.startBeat + $0.durationInBeats }.max() ?? 0.0
        
        // Convert segment length from measures to beats
        let beatsPerMeasure = Double(preset.timeSignature.beatsPerMeasure)
        let durationInBeats = Double(accompanimentSegment.lengthInMeasures) * beatsPerMeasure
        
        let newSegment = GuitarSegment(
            startBeat: lastBeat,
            durationInBeats: durationInBeats,
            type: .accompaniment(segmentId: accompanimentSegment.id)
        )
        
        appData.preset?.arrangement.guitarTracks[trackIndex].segments.append(newSegment)
        appData.saveChanges()
    }
}

// This wrapper holds a mutable copy of the segment for editing,
// preventing direct modification of the main data store until save is clicked.
private struct EditorWrapperView: View {
    @State var segment: AccompanimentSegment
    let isNew: Bool
    let onSave: (AccompanimentSegment) -> Void
    let onCancel: () -> Void

    init(segmentToEdit: AccompanimentSegment, isNew: Bool, onSave: @escaping (AccompanimentSegment) -> Void, onCancel: @escaping () -> Void) {
        self._segment = State(initialValue: segmentToEdit)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        AccompanimentEditorView(
            segment: $segment, // Pass binding to the local, mutable copy
            isNew: isNew,
            onSave: { _ in onSave(segment) }, // On save, pass the modified copy back
            onCancel: onCancel
        )
    }
}
