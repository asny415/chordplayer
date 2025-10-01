
import SwiftUI

struct MelodicLyricSegmentsView: View {
    @EnvironmentObject var appData: AppData
    @Binding var segmentToEdit: MelodicLyricSegment?

    // Define the grid layout
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
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
            
            // Grid of lyric segments or empty state view
            if let preset = appData.preset, !preset.melodicLyricSegments.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(preset.melodicLyricSegments.enumerated()), id: \.element.id) { index, segment in
                        MelodicLyricSegmentCard(
                            segment: segment,
                            isActive: false, // Placeholder for now
                            onEdit: { self.segmentToEdit = segment },
                            onDelete: { deleteSegment(at: IndexSet(integer: index)) },
                            onDuplicate: { duplicateSegment(segment: segment) },
                            onAddToTrack: { trackId in
                                self.addToLyricsTrack(segment: segment, trackId: trackId)
                            }
                        )
                    }
                }
            } else {
                // More engaging empty state
                VStack(spacing: 12) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Melodic Lyric Segments")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Create lyric segments to add vocal melodies to your preset.")
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    
                    Button("Create First Lyric Segment", action: addSegment)
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
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

    private func deleteSegment(at offsets: IndexSet) {
        guard appData.preset != nil else { return }
        appData.preset!.melodicLyricSegments.remove(atOffsets: offsets)
        appData.saveChanges()
    }
    
    private func duplicateSegment(segment: MelodicLyricSegment) {
        guard appData.preset != nil, let index = appData.preset!.melodicLyricSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        
        var newSegment = segment
        newSegment.id = UUID()
        newSegment.name = "\(segment.name) 2"
        
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
