
import SwiftUI

struct MelodicLyricSegmentsView: View {
    @EnvironmentObject var appData: AppData
    @Binding var segmentToEdit: MelodicLyricSegment?
    
    @State private var segmentToDelete: MelodicLyricSegment? = nil
    @State private var showingDeleteConfirmation = false

    // Define the grid layout
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading) {
            if let preset = appData.preset, !preset.melodicLyricSegments.isEmpty {
                // Header with title and add button
                HStack {
                    Text("Melodic Lyric Segments").font(.headline)
                    Spacer()
                    
                    Button(action: addSegment) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new lyric segment")
                }
                
                // Grid of lyric segments
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(preset.melodicLyricSegments) { segment in
                        SegmentCardView(
                            title: segment.name,
                            systemImageName: "music.mic",
                            isSelected: false // Active state not used for lyric segments currently
                        ) {
                            MelodicLyricCardContent(segment: segment)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { // Double-tap to edit
                            self.segmentToEdit = segment
                        }
                        .contextMenu {
                            contextMenuFor(segment: segment)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    imageName: "music.mic",
                    text: "Create a Melodic Lyric",
                    action: addSegment
                )
            }
        }
        .alert("Delete \(segmentToDelete?.name ?? "Segment")", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) { segmentToDelete = nil }
        } message: {
            Text("Are you sure you want to delete this lyric segment? This action cannot be undone.")
        }
    }
    
    @ViewBuilder
    private func contextMenuFor(segment: MelodicLyricSegment) -> some View {
        if let preset = appData.preset {
            let lyricsTracks = preset.arrangement.lyricsTracks
            if !lyricsTracks.isEmpty {
                Menu("Add to Arrangement") {
                    ForEach(lyricsTracks) { track in
                        Button("\(track.name)") {
                            addToLyricsTrack(segment: segment, trackId: track.id)
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
            duplicateSegment(segment: segment)
        }
        Divider()
        Button("Delete", role: .destructive) {
            self.segmentToDelete = segment
            self.showingDeleteConfirmation = true
        }
    }

    private func addSegment() {
        guard appData.preset != nil else { return }
        let count = appData.preset?.melodicLyricSegments.count ?? 0
        let newSegment = MelodicLyricSegment(name: "Lyric \(count + 1)", lengthInBars: 4)
        appData.preset!.melodicLyricSegments.append(newSegment)
        appData.saveChanges()
        self.segmentToEdit = newSegment
    }

    private func confirmDelete() {
        guard let segment = segmentToDelete, let index = appData.preset?.melodicLyricSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        deleteSegment(at: IndexSet(integer: index))
        segmentToDelete = nil
    }
    
    private func deleteSegment(at offsets: IndexSet) {
        guard appData.preset != nil else { return }
        appData.preset!.melodicLyricSegments.remove(atOffsets: offsets)
        appData.saveChanges()
    }
    
    private func duplicateSegment(segment: MelodicLyricSegment) {
        guard appData.preset != nil, let index = appData.preset!.melodicLyricSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        
        var newSegment = segment
        newSegment.id = UUID()
        newSegment.name = "\(segment.name) Copy"
        
        appData.preset!.melodicLyricSegments.insert(newSegment, at: index + 1)
        appData.saveChanges()
    }
    
    private func addToLyricsTrack(segment: MelodicLyricSegment, trackId: UUID) {
        guard let preset = appData.preset, 
              let trackIndex = preset.arrangement.lyricsTracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        let track = preset.arrangement.lyricsTracks[trackIndex]
        
        // Calculate the end beat of the last segment on this track
        let lastBeat = track.lyrics.map { $0.startBeat + $0.durationInBeats }.max() ?? 0.0
        
        // Convert segment length from bars to beats
        let beatsPerMeasure = Double(preset.timeSignature.beatsPerMeasure)
        let durationInBeats = Double(segment.lengthInBars) * beatsPerMeasure
        
        // Create a summary text for the new segment
        let summaryText = segment.items.map { $0.word }.joined()
        
        let newSegment = LyricsSegment(
            melodicLyricSegmentId: segment.id,
            startBeat: lastBeat,
            durationInBeats: durationInBeats,
            text: summaryText.isEmpty ? segment.name : summaryText
        )
        
        appData.preset?.arrangement.lyricsTracks[trackIndex].lyrics.append(newSegment)
        // The .onChange handler in PresetWorkspaceView will automatically update the total length
        appData.saveChanges()
    }
}
