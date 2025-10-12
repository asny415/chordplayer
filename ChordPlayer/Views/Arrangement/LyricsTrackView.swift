
import SwiftUI

struct LyricsTrackView: View {
    @Binding var track: LyricsTrack
    @Binding var preset: Preset
    let pixelsPerBeat: CGFloat
    var onRemove: ((UUID) -> Void)? = nil
    var onRemoveTrack: ((UUID) -> Void)? = nil
    @EnvironmentObject var appData: AppData
    @State private var showingAlert = false

    var body: some View {
        HStack(spacing: 0) {
            // Track Header
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.headline)
                
                Text("Ch: \(track.midiChannel ?? 1)")
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
            .contextMenu {
                Button(action: {
                    if track.lyrics.isEmpty {
                        onRemoveTrack?(track.id)
                    } else {
                        showingAlert = true
                    }
                }) {
                    Label("移除轨道", systemImage: "trash")
                }
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("无法移除轨道"), message: Text("轨道非空，不可删除。"), dismissButton: .default(Text("好")))
            }

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
                                appData.saveChanges()
                            }
                        },
                        onRemove: {
                            onRemove?(segment.id)
                        }
                    )
                }
            }
            .frame(height: 50)
        }
    }
}
