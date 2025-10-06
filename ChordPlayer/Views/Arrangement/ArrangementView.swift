
import SwiftUI

struct ArrangementView: View {
    @EnvironmentObject var appData: AppData
    @Binding var arrangement: SongArrangement
    @Binding var preset: Preset
    @Binding var playheadPosition: Double

    // Define a constant for pixels per beat to ensure consistency
    private let pixelsPerBeat: CGFloat = 30.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header for the arrangement section
            HStack {
                Text("歌曲编排 (Arrangement)")
                    .font(.headline)
                Spacer()
                
                // Add guitar track or lyrics track dropdown
                Menu {
                    Button(action: {
                        arrangement.addGuitarTrack()
                    }) {
                        Label("添加吉他轨道", systemImage: "guitars.fill")
                    }
                    
                    Button(action: {
                        arrangement.addLyricsTrack()
                    }) {
                        Label("添加歌词轨道", systemImage: "text.quote")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("添加吉他轨道或歌词轨道")
            }
            .padding(.bottom, 5)

            // A single ScrollView for the ruler and all tracks to ensure synchronized scrolling
            ScrollView([.horizontal, .vertical]) {
                // Calculate the total width of the timeline content outside the VStack
                let totalWidth = max(1200, pixelsPerBeat * arrangement.lengthInBeats)
                VStack(alignment: .leading, spacing: 4) {

                    // 1. The real Timeline Ruler, wrapped in an HStack to align with track headers
                    HStack(spacing: 0) {
                        // Spacer to align with track headers
                        Rectangle().fill(Color.clear).frame(width: 120)
                        
                        TimelineRulerView(
                            playheadPosition: $playheadPosition,
                            lengthInBeats: arrangement.lengthInBeats,
                            timeSignature: preset.timeSignature,
                            pixelsPerBeat: pixelsPerBeat
                        )
                    }
                    .frame(height: 24)

                    // 2. The Tracks
                    DrumTrackView(
                        track: $arrangement.drumTrack,
                        preset: $preset,
                        pixelsPerBeat: pixelsPerBeat,
                        onRemove: removeDrumSegment
                    )

                    ForEach($arrangement.guitarTracks) { $track in
                        GuitarTrackView(
                            track: $track,
                            preset: $preset,
                            pixelsPerBeat: pixelsPerBeat,
                            onRemove: { segmentId in
                                removeGuitarSegment(segmentId: segmentId, from: track.id)
                            }
                        )
                    }

                    ForEach($arrangement.lyricsTracks) { $track in
                        LyricsTrackView(
                            track: $track,
                            preset: $preset,
                            pixelsPerBeat: pixelsPerBeat,
                            onRemove: { segmentId in
                                removeLyricsSegment(segmentId: segmentId, from: track.id)
                            }
                        )
                    }
                }
                .padding(.top, 4)
                // Apply the calculated total width to the VStack containing all timeline content
                .frame(minWidth: totalWidth + 120)
                .overlay(
                    // GeometryReader to get the full height of the content for the playhead line
                    GeometryReader { geometry in
                        PlayheadView()
                            .frame(height: geometry.size.height)
                            .offset(x: 120 + (playheadPosition * pixelsPerBeat)) // 120 for track header width
                    }
                )
            }
        }
    }
    
    // MARK: - Segment Removal Methods
    
    private func removeDrumSegment(segmentId: UUID) {
        arrangement.drumTrack.segments.removeAll { $0.id == segmentId }
        appData.saveChanges()
    }
    
    private func removeGuitarSegment(segmentId: UUID, from trackId: UUID) {
        if let trackIndex = arrangement.guitarTracks.firstIndex(where: { $0.id == trackId }) {
            arrangement.guitarTracks[trackIndex].removeSegment(withId: segmentId)
            appData.saveChanges()
        }
    }
    
    private func removeLyricsSegment(segmentId: UUID, from trackId: UUID) {
        if let trackIndex = arrangement.lyricsTracks.firstIndex(where: { $0.id == trackId }) {
            arrangement.lyricsTracks[trackIndex].removeLyrics(withId: segmentId)
            appData.saveChanges()
        }
    }
}
