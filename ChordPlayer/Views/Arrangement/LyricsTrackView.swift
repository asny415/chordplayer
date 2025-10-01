
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

                // Iterate over segments and place them on the timeline using the new SegmentView
                ForEach(track.lyrics) { segment in
                    SegmentView(
                        text: segment.text,
                        color: .orange,
                        startBeat: segment.startBeat,
                        durationInBeats: segment.durationInBeats,
                        pixelsPerBeat: pixelsPerBeat,
                        onMove: { newBeat in
                            if let index = track.lyrics.firstIndex(where: { $0.id == segment.id }) {
                                track.lyrics[index].startBeat = newBeat
                            }
                        }
                    )
                }
            }
            .frame(height: 50)
        }
    }
}
