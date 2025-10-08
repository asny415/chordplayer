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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 10) {
                    ForEach(preset.accompanimentSegments) { segment in
                        let isActive = appData.preset?.activeAccompanimentSegmentId == segment.id
                        AccompanimentSegmentCardView(
                            segment: segment,
                            isActive: isActive,
                            onSelect: {
                                appData.preset?.activeAccompanimentSegmentId = segment.id
                                appData.saveChanges()
                            },
                            onEdit: {
                                self.segmentToEdit = segment
                            },
                            onDelete: {
                                if let index = appData.preset?.accompanimentSegments.firstIndex(where: { $0.id == segment.id }) {
                                    appData.removeAccompanimentSegment(at: IndexSet(integer: index))
                                }
                            },
                            onNameChange: { newName in
                                if let index = appData.preset?.accompanimentSegments.firstIndex(where: { $0.id == segment.id }) {
                                    appData.preset?.accompanimentSegments[index].name = newName
                                    appData.saveChanges()
                                }
                            },
                            onAddToTrack: { trackId in
                                self.addToGuitarTrack(accompanimentSegment: segment, trackId: trackId)
                            }
                        )

                    }
                }
            } else {
                EmptyStateView(
                    imageName: "pianokeys",
                    text: "创建伴奏片段",
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

struct AccompanimentSegmentCardView: View {
    let segment: AccompanimentSegment
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNameChange: (String) -> Void
    let onAddToTrack: (UUID) -> Void
    
    @EnvironmentObject var appData: AppData
    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditingName {
                TextField("Segment Name", text: $editedName)
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        onNameChange(editedName)
                        isEditingName = false
                    }
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(segment.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .onTapGesture(count: 2) {
                        editedName = segment.name
                        isEditingName = true
                        isNameFieldFocused = true
                    }
            }

            if let chordProgression = getChordProgressionPreview() {
                Text(chordProgression)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text("\(segment.lengthInMeasures) measures")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(8)
        .frame(width: 160, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                onSelect()
            }
        }
        .contextMenu {
            if let preset = appData.preset {
                let guitarTracks = preset.arrangement.guitarTracks
                if !guitarTracks.isEmpty {
                    if guitarTracks.count == 1,
                       let firstTrack = guitarTracks.first {
                        Button("Add to \(firstTrack.name)") {
                            onAddToTrack(firstTrack.id)
                        }
                    } else {
                        Menu("Add to Arrangement") {
                            ForEach(guitarTracks) { track in
                                Button("\(track.name)") {
                                    onAddToTrack(track.id)
                                }
                            }
                        }
                    }
                    Divider()
                }
            }
            
            Button("Edit", action: onEdit)
            Button("Duplicate") {
                var duplicatedSegment = segment
                duplicatedSegment.id = UUID()
                duplicatedSegment.name = "\(segment.name) Copy"
                appData.addAccompanimentSegment(duplicatedSegment)
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func getChordProgressionPreview() -> String? {
        guard let preset = appData.preset, !segment.measures.isEmpty else { return nil }

        let allChordIds = segment.measures.flatMap { $0.chordEvents }.map { $0.resourceId }
        
        if allChordIds.isEmpty {
            return "(No Chords)"
        }

        let uniqueChordNames: [String] = allChordIds.removingDuplicates().compactMap { chordId in
            preset.chords.first { $0.id == chordId }?.name
        }

        if uniqueChordNames.isEmpty {
            return "(No Chords)"
        }

        return uniqueChordNames.prefix(4).joined(separator: " → ")
    }
}
