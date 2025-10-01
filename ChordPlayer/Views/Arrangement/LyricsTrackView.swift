
import SwiftUI

struct LyricsTrackView: View {
    @Binding var track: LyricsTrack
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
                ForEach(track.lyrics) { segment in
                    let segmentWidth = pixelsPerBeat * segment.durationInBeats
                    let xPosition = pixelsPerBeat * segment.startBeat

                    // Group the segment view and its text in a ZStack, then offset the whole group
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.7))

                        Text(segment.text)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .clipped()
                    }
                    .frame(width: segmentWidth)
                    .offset(x: xPosition)
                }
            }
            .frame(height: 50)
        }
    }
}
