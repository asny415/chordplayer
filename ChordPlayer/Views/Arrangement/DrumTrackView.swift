
import SwiftUI

struct DrumTrackView: View {
    @Binding var track: DrumTrack
    @Binding var preset: Preset
    let pixelsPerBeat: CGFloat
    @EnvironmentObject var appData: AppData

    var body: some View {
        HStack(spacing: 0) {
            // Track Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Drum")
                    .font(.headline)
                
                Text("Ch: \(track.midiChannel ?? 10)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .contextMenu {
                        ForEach(1...16, id: \.self) { channel in
                            Button("Channel \(channel)") {
                                track.midiChannel = channel
                                appData.saveChanges()
                            }
                        }
                    }
                Spacer()
            }
            .padding(4)
            .frame(width: 120, alignment: .leading)
            .background(Color.gray.opacity(0.1))

            // Timeline area for the segments
            ZStack(alignment: .leading) {
                // Background of the timeline
                Rectangle()
                    .fill(Color.gray.opacity(0.15))

                // Iterate over segments and place them on the timeline using the new SegmentView
                ForEach(track.segments) { segment in
                    SegmentView(
                        text: preset.drumPatterns.first { $0.id == segment.patternId }?.name ?? "Unknown",
                        color: .blue,
                        startBeat: segment.startBeat,
                        durationInBeats: segment.durationInBeats,
                        pixelsPerBeat: pixelsPerBeat,
                        onMove: { newBeat in
                            // Find the index of the segment that was moved
                            if let index = track.segments.firstIndex(where: { $0.id == segment.id }) {
                                // Update the startBeat in the data model. The @Binding will handle the rest.
                                track.segments[index].startBeat = newBeat
                            }
                        }
                    )
                }
            }
            .frame(height: 50)
        }
    }
}
