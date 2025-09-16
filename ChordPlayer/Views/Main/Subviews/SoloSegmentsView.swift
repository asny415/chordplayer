import SwiftUI

struct SoloSegmentsView: View {
    @EnvironmentObject var appData: AppData
    @Binding var segmentToEdit: SoloSegment?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题和操作按钮
            HStack {
                Text("Solo Segments").font(.headline)
                Spacer()
                
                Button(action: {
                    let count = appData.preset?.soloSegments.count ?? 0
                    let newSegment = SoloSegment(name: "New Solo \(count + 1)", lengthInBeats: 4.0)
                    appData.preset?.soloSegments.append(newSegment)
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
            if let preset = appData.preset, !preset.soloSegments.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                    ForEach(preset.soloSegments) { segment in
                        SoloSegmentCard(
                            segment: segment,
                            isActive: preset.activeSoloSegmentId == segment.id,
                            onSelect: {
                                appData.preset?.activeSoloSegmentId = segment.id
                                appData.saveChanges()
                            },
                            onEdit: {
                                self.segmentToEdit = segment
                            }
                        )
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No solo segments defined")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Create solo segments to add melodic content to your preset")
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Create First Solo") {
                        let newSegment = SoloSegment(name: "New Solo", lengthInBeats: 4.0)
                        appData.preset?.soloSegments.append(newSegment)
                        self.segmentToEdit = newSegment
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }
}

struct SoloSegmentCard: View {
    let segment: SoloSegment
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    
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
                Button(action: onSelect) {
                    Text(isActive ? "Active" : "Select")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isActive)
                
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
        .onTapGesture {
            if !isActive {
                onSelect()
            }
        }
        .contextMenu {
            Button("Select", action: onSelect)
                .disabled(isActive)
            
            Button("Edit", action: onEdit)
            
            Divider()
            
            Button("Duplicate") {
                // TODO: 实现复制功能
            }
            
            Button("Delete", role: .destructive) {
                // TODO: 实现删除功能
            }
        }
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