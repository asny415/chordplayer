
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
                            onDelete: { deleteSegment(at: IndexSet(integer: index)) }
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
        self.segmentToEdit = newSegment
    }

    private func deleteSegment(at offsets: IndexSet) {
        guard appData.preset != nil else { return }
        appData.preset!.melodicLyricSegments.remove(atOffsets: offsets)
    }
}
