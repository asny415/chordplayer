
import SwiftUI

struct GuitarTrackView: View {
    @Binding var track: GuitarTrack
    @Binding var preset: Preset
    let pixelsPerBeat: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // TODO: Replace with a dedicated TrackHeaderView
            Text(track.name)
                .font(.headline)
                .padding(.horizontal, 4)
                .frame(width: 120, alignment: .leading)
                .background(Color.gray.opacity(0.1))

            // Timeline area for the segments
            ZStack(alignment: .leading) {
                // Background of the timeline
                Rectangle()
                    .fill(Color.gray.opacity(0.15))

                // Iterate over segments and place them on the timeline
                ForEach(track.segments) { segment in
                    let segmentWidth = pixelsPerBeat * segment.durationInBeats
                    let xPosition = pixelsPerBeat * segment.startBeat

                    // Group the segment view and its text in a ZStack, then offset the whole group
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorFor(segmentType: segment.type).opacity(0.7))
                        
                        Text(segmentName(for: segment.type))
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                    }
                    .frame(width: segmentWidth)
                    .offset(x: xPosition)
                }
            }
            .frame(height: 50)
        }
    }
    
    private func segmentName(for type: GuitarSegmentType) -> String {
        switch type {
        case .solo(let segmentId):
            return preset.soloSegments.first { $0.id == segmentId }?.name ?? "Solo"
        case .accompaniment(let segmentId):
            return preset.accompanimentSegments.first { $0.id == segmentId }?.name ?? "Accompaniment"
        }
    }
    
    private func colorFor(segmentType: GuitarSegmentType) -> Color {
        switch segmentType {
        case .solo:
            return .purple
        case .accompaniment:
            return .green
        }
    }
}
