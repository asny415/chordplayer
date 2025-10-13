import SwiftUI

// The new content view, containing the details previously in SoloSegmentCard
struct SoloCardContent: View {
    let segment: SoloSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 统计信息
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Length")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(String(format: "%.1f", segment.lengthInBeats)) beats")
                        .font(.system(.subheadline, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(segment.notes.count)")
                        .font(.system(.subheadline, design: .monospaced))
                }
            }
            
            // 简化的音符预览
            if !segment.notes.isEmpty {
                SoloPreviewView(segment: segment)
                    .frame(height: 30)
            }
        }
    }
}


struct SoloSegmentsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var soloPlayer: SoloPlayer
    @Binding var segmentToEdit: SoloSegment?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let preset = appData.preset, !preset.soloSegments.isEmpty {
                // 标题和操作按钮
                HStack {
                    Text("Solo Segments").font(.headline)
                    Spacer()
                    
                    Button(action: {
                        let count = appData.preset?.soloSegments.count ?? 0
                        let newSegment = SoloSegment(name: "New Solo \(count + 1)", lengthInBeats: 4.0)
                        appData.addSoloSegment(newSegment)
                        self.segmentToEdit = newSegment
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Create a new solo segment")
                }
                
                // Solo列表概览
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                    ForEach(Array(preset.soloSegments.enumerated()), id: \.element.id) { index, segment in
                        let isActive = preset.activeSoloSegmentId == segment.id
                        
                        SegmentCardView(
                            title: segment.name,
                            systemImageName: "waveform.path.ecg",
                            isSelected: isActive
                        ) {
                            SoloCardContent(segment: segment)
                        }
                        .onTapGesture(count: 2) {
                            self.segmentToEdit = segment
                        }
                        .onTapGesture {
                            appData.preset?.activeSoloSegmentId = segment.id
                            appData.saveChanges()
                            soloPlayer.play(segment: segment)
                        }
                        .contextMenu {
                            contextMenuFor(segment: segment, index: index)
                        }
                    }
                }
            } else {
                EmptyStateView(
                    imageName: "waveform.path.ecg",
                    text: "创建独奏片段",
                    action: {
                        let count = appData.preset?.soloSegments.count ?? 0
                        let newSegment = SoloSegment(name: "New Solo \(count + 1)", lengthInBeats: 4.0)
                        appData.addSoloSegment(newSegment)
                        self.segmentToEdit = newSegment
                    }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let count = appData.preset?.soloSegments.count ?? 0
            let newSegment = SoloSegment(name: "New Solo \(count + 1)", lengthInBeats: 4.0)
            appData.addSoloSegment(newSegment)
            self.segmentToEdit = newSegment
        }
    }
    
    @ViewBuilder
    private func contextMenuFor(segment: SoloSegment, index: Int) -> some View {
        if let preset = appData.preset {
            let guitarTracks = preset.arrangement.guitarTracks
            if !guitarTracks.isEmpty {
                Menu("Add to Arrangement") {
                    ForEach(guitarTracks) { track in
                        Button("\(track.name)") {
                            addToGuitarTrack(soloSegment: segment, trackId: track.id)
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
            var duplicatedSegment = segment
            duplicatedSegment.id = UUID()
            duplicatedSegment.name = "\(segment.name) Copy"
            appData.addSoloSegment(duplicatedSegment)
        }
        Button("Delete", role: .destructive) {
            appData.removeSoloSegment(at: IndexSet(integer: index))
        }
    }
    
    private func addToGuitarTrack(soloSegment: SoloSegment, trackId: UUID) {
        guard let preset = appData.preset, 
              let trackIndex = preset.arrangement.guitarTracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        let track = preset.arrangement.guitarTracks[trackIndex]
        
        // Calculate the end beat of the last segment on this track
        let lastBeat = track.segments.map { $0.startBeat + $0.durationInBeats }.max() ?? 0.0
        
        let newSegment = GuitarSegment(
            startBeat: lastBeat,
            durationInBeats: soloSegment.lengthInBeats,
            type: .solo(segmentId: soloSegment.id)
        )
        
        appData.preset?.arrangement.guitarTracks[trackIndex].segments.append(newSegment)
        appData.saveChanges()
    }
}

struct SoloPreviewView: View {
    let segment: SoloSegment
    
    private let stringPositions: [CGFloat] = [5, 10, 15, 20, 25, 30]
    
    var body: some View {
        Canvas { context, size in
            let totalWidth = size.width
            let totalBeats = segment.lengthInBeats
            
            // 绘制弦线
            for y in stringPositions {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: totalWidth, y: y))
                    },
                    with: .color(.secondary.opacity(0.3)),
                    lineWidth: 0.5
                )
            }
            
            // 绘制音符
            for note in segment.notes {
                let x = (note.startTime / totalBeats) * totalWidth
                let y = stringPositions[min(note.string, 5)]
                
                context.fill(
                    Path { path in
                        path.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                    },
                    with: .color(.accentColor)
                )
            }
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(4)
    }
}