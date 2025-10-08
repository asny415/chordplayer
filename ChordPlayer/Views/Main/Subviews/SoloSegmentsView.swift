import SwiftUI

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
                        SoloSegmentCard(
                            segment: segment,
                            isActive: preset.activeSoloSegmentId == segment.id,
                            onSelect: {
                                appData.preset?.activeSoloSegmentId = (preset.activeSoloSegmentId == segment.id) ? nil : segment.id
                                appData.saveChanges()
                            },
                            onEdit: {
                                self.segmentToEdit = segment
                            },
                            onDelete: {
                                appData.removeSoloSegment(at: IndexSet(integer: index))
                            },
                            onNameChange: { newName in
                                var updatedSegment = segment
                                updatedSegment.name = newName
                                appData.updateSoloSegment(updatedSegment)
                            },
                            onAddToTrack: { trackId in
                                self.addToGuitarTrack(soloSegment: segment, trackId: trackId)
                            }
                        )
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

struct SoloSegmentCard: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var soloPlayer: SoloPlayer
    let segment: SoloSegment
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onNameChange: (String) -> Void
    let onAddToTrack: (UUID) -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                Text(segment.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
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
            
            // 操作按钮
            HStack {
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit this solo")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onEdit()
        }
        .onTapGesture {
            onSelect()
            if !isActive {
                soloPlayer.play(segment: segment)
            }
        }
        .contextMenu {
            if let preset = appData.preset {
                let guitarTracks = preset.arrangement.guitarTracks
                if !guitarTracks.isEmpty {
                    if guitarTracks.count == 1,
                       let firstTrack = guitarTracks.first {
                        Button("Add to \(firstTrack.name)") {
                            onAddToTrack(firstTrack.id)
                        }
                    } else {
                        Menu("Add to Arrangement") {
                            ForEach(guitarTracks) { track in
                                Button("\(track.name)") {
                                    onAddToTrack(track.id)
                                }
                            }
                        }
                    }
                    Divider()
                }
            }

            Button("Edit", action: onEdit)
            Divider()
            Button("Delete", role: .destructive) {
                showingDeleteConfirmation = true
            }
        }
        .alert("Delete \(segment.name)", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this solo segment? This action cannot be undone.")
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
