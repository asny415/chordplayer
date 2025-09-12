import SwiftUI

struct LyricsManagerView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) private var dismiss
    
    @State private var sortedLyrics: [Lyric] = []
    @State private var showAddLyricForm = false
    @State private var editingLyric: Lyric? = nil
    @State private var newLyricContent = ""
    @State private var newTimeRanges: [LyricTimeRange] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("歌词管理")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            HSplitView {
                // Left side: Lyrics list
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("歌词列表")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: addNewLyric) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("添加新歌词")
                    }
                    .padding()
                    
                    if sortedLyrics.isEmpty {
                        VStack {
                            Spacer()
                            Text("暂无歌词")
                                .foregroundColor(.secondary)
                                .font(.title3)
                            Text("点击 + 添加第一条歌词")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(sortedLyrics) { lyric in
                                LyricRowView(
                                    lyric: lyric,
                                    onEdit: { startEditingLyric($0) },
                                    onDelete: { deleteLyric($0) }
                                )
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                .frame(minWidth: 400)
                
                // Right side: Add/Edit form
                VStack {
                    if showAddLyricForm || editingLyric != nil {
                        LyricFormView(
                            content: $newLyricContent,
                            timeRanges: $newTimeRanges,
                            isEditing: editingLyric != nil,
                            onSave: saveLyric,
                            onCancel: cancelForm
                        )
                    } else {
                        VStack {
                            Spacer()
                            Text("选择歌词进行编辑")
                                .foregroundColor(.secondary)
                                .font(.title3)
                            Text("或点击 + 添加新歌词")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
                .frame(minWidth: 300)
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            updateAndSortLyrics()
        }
    }
    
    private func updateAndSortLyrics() {
        sortedLyrics = appData.performanceConfig.lyrics.sorted(by: { $0.earliestStartBeat ?? 0 < $1.earliestStartBeat ?? 0 })
    }
    
    private func addNewLyric() {
        newLyricContent = ""
        newTimeRanges = [LyricTimeRange(startBeat: 1, endBeat: 1)]
        editingLyric = nil
        showAddLyricForm = true
    }
    
    private func saveLyric() {
        var currentLyrics = appData.performanceConfig.lyrics
        
        if let editingLyric = editingLyric {
            // Update existing lyric
            if let index = currentLyrics.firstIndex(where: { $0.id == editingLyric.id }) {
                var updatedLyric = currentLyrics[index]
                updatedLyric.content = newLyricContent
                updatedLyric.timeRanges = newTimeRanges
                currentLyrics[index] = updatedLyric
            }
        } else {
            // Add new lyric
            let lyric = Lyric(content: newLyricContent, timeRanges: newTimeRanges)
            currentLyrics.append(lyric)
        }
        
        // Save back to appData
        appData.performanceConfig.lyrics = currentLyrics
        updateAndSortLyrics()
        
        // Reset form
        cancelForm()
    }
    
    private func deleteLyric(_ lyric: Lyric) {
        appData.performanceConfig.lyrics.removeAll { $0.id == lyric.id }
        updateAndSortLyrics()
        
        // If the deleted lyric was being edited, cancel editing
        if editingLyric?.id == lyric.id {
            cancelForm()
        }
    }
    
    private func cancelForm() {
        showAddLyricForm = false
        editingLyric = nil
        newLyricContent = ""
        newTimeRanges = []
    }
    
    private func startEditingLyric(_ lyric: Lyric) {
        editingLyric = lyric
        newLyricContent = lyric.content
        newTimeRanges = lyric.timeRanges
        showAddLyricForm = false
    }
}

private struct LyricRowView: View {
    let lyric: Lyric
    let onEdit: (Lyric) -> Void
    let onDelete: (Lyric) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(lyric.content)
                    .font(.body)
                    .lineLimit(2)
                
                Text(formatTimeRangesDisplay(lyric.timeRanges))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { onEdit(lyric) }) {
                Image(systemName: "pencil")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("编辑")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit(lyric)
        }
        .contextMenu {
            Button("编辑") {
                onEdit(lyric)
            }
            
            Button("删除", role: .destructive) {
                onDelete(lyric)
            }
        }
    }
    
    private func formatTimeRangesDisplay(_ timeRanges: [LyricTimeRange]) -> String {
        if timeRanges.isEmpty {
            return "无时间段"
        }
        
        let sorted = timeRanges.sorted { $0.startBeat < $1.startBeat }
        let rangeStrings = sorted.map { "第 \($0.startBeat)-\($0.endBeat) 拍" }
        let totalBeats = timeRanges.reduce(0) { $0 + $1.durationBeats }
        
        return rangeStrings.joined(separator: ", ") + " (共 \(totalBeats) 拍)"
    }
}

private struct LyricFormView: View {
    @Binding var content: String
    @Binding var timeRanges: [LyricTimeRange]
    let isEditing: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "编辑歌词" : "添加歌词")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("歌词内容")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextEditor(text: $content)
                    .font(.body)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("时间段")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button(action: addTimeRange) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("添加时间段")
                }
                
                if timeRanges.isEmpty {
                    Text("至少需要一个时间段")
                        .foregroundColor(.red)
                        .font(.caption)
                } else {
                    ForEach(timeRanges.indices, id: \.self) { index in
                        TimeRangeRowView(
                            timeRange: $timeRanges[index],
                            canDelete: timeRanges.count > 1,
                            onDelete: { removeTimeRange(at: index) }
                        )
                    }
                }
            }
            
            Spacer()
            
            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button(isEditing ? "保存" : "添加") {
                    onSave()
                }
                .keyboardShortcut(.return)
                .disabled(
                    content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    timeRanges.isEmpty ||
                    timeRanges.contains { $0.endBeat < $0.startBeat }
                )
            }
        }
        .padding()
    }
    
    private func addTimeRange() {
        let newRange = LyricTimeRange(startBeat: 1, endBeat: 1)
        timeRanges.append(newRange)
    }
    
    private func removeTimeRange(at index: Int) {
        guard timeRanges.count > 1 else { return }
        timeRanges.remove(at: index)
    }
}

private struct TimeRangeRowView: View {
    @Binding var timeRange: LyricTimeRange
    let canDelete: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("开始拍号")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("开始", value: $timeRange.startBeat, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("结束拍号")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("结束", value: $timeRange.endBeat, formatter: NumberFormatter())
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 80)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("持续时长")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if timeRange.endBeat >= timeRange.startBeat {
                    Text("\(timeRange.durationBeats) 拍")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("无效范围")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除时间段")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    LyricsManagerView()
        .environmentObject(AppData(customChordManager: CustomChordManager.shared))
}