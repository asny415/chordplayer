import SwiftUI

struct PresetArrangementView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var presetArrangerPlayer: PresetArrangerPlayer

    @State private var showingArrangerSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题和控制按钮
            HStack {
                Text("Song Arrangement")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // 播放控制
                Button(action: {
                    if presetArrangerPlayer.isPlaying {
                        presetArrangerPlayer.stop()
                    } else {
                        presetArrangerPlayer.playCurrentPresetArrangement()
                    }
                }) {
                    Image(systemName: presetArrangerPlayer.isPlaying ? "stop.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appData.preset == nil)

                Button("Edit Arrangement") {
                    showingArrangerSheet = true
                }
                .buttonStyle(.bordered)
                .disabled(appData.preset == nil)
            }

            if let preset = appData.preset {
                // 编排统计信息
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.blue)
                        Text("Length: \(String(format: "%.0f", preset.arrangement.lengthInBeats / 4)) measures (\(String(format: "%.0f", preset.arrangement.lengthInBeats)) beats)")
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: "drum.fill")
                            .foregroundColor(.orange)
                        Text("Drum segments: \(preset.arrangement.drumTrack.segments.count)")
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: "guitars")
                            .foregroundColor(.blue)
                        Text("Guitar tracks: \(preset.arrangement.guitarTracks.count)")
                            .font(.subheadline)
                    }

                    if !preset.arrangement.annotationTrack.annotations.isEmpty {
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.purple)
                            Text("Annotations: \(preset.arrangement.annotationTrack.annotations.count)")
                                .font(.subheadline)
                        }
                    }

                    if !preset.arrangement.lyricsTrack.lyrics.isEmpty {
                        HStack {
                            Image(systemName: "text.justify")
                                .foregroundColor(.gray)
                            Text("Lyrics segments: \(preset.arrangement.lyricsTrack.lyrics.count)")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // 轨道预览
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tracks Overview")
                        .font(.headline)

                    ForEach(preset.arrangement.guitarTracks) { track in
                        HStack {
                            Image(systemName: "guitars")
                                .foregroundColor(track.isMuted ? .secondary : .blue)
                            Text(track.name)
                                .font(.subheadline)
                                .strikethrough(track.isMuted)
                            Spacer()
                            Text("\(track.segments.count) segments")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                // 空状态
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No preset loaded")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Load a preset to start arranging your song")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .padding()
        .sheet(isPresented: $showingArrangerSheet) {
            if let preset = appData.preset {
                NavigationStack {
                    SimplePresetArrangerView()
                        .navigationTitle("Arrange: \(preset.name)")
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Done") {
                                    showingArrangerSheet = false
                                }
                            }
                        }
                }
                .frame(minWidth: 900, minHeight: 600)
            }
        }
    }
}

// 完整的Preset编排编辑器，包含拖拽功能
struct SimplePresetArrangerView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var presetArrangerPlayer: PresetArrangerPlayer

    @State private var zoomLevel: CGFloat = 1.0
    @State private var selectedSegmentId: UUID?
    @State private var showingResourcePanel: Bool = true
    @State private var editingDrumSegment: DrumSegment?
    @State private var editingGuitarSegment: GuitarSegment?
    @State private var showingDurationEditor: Bool = false

    // 时间轴设置
    private let beatWidth: CGFloat = 60
    private let trackHeight: CGFloat = 60
    private let headerHeight: CGFloat = 40

    var arrangement: SongArrangement {
        appData.preset?.arrangement ?? SongArrangement()
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            ArrangementToolbar(
                arrangement: arrangement,
                isPlaying: presetArrangerPlayer.isPlaying,
                zoomLevel: $zoomLevel,
                onPlay: {
                    if presetArrangerPlayer.isPlaying {
                        presetArrangerPlayer.stop()
                    } else {
                        presetArrangerPlayer.playCurrentPresetArrangement()
                    }
                },
                onUpdateLength: { newLength in
                    updateArrangementLength(newLength)
                }
            )
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 主编辑区域
            HSplitView {
                // 左侧时间轴编辑器
                ArrangementTimelineView(
                    arrangement: arrangement,
                    selectedSegmentId: $selectedSegmentId,
                    zoomLevel: zoomLevel,
                    beatWidth: beatWidth,
                    trackHeight: trackHeight,
                    headerHeight: headerHeight,
                    playbackPosition: presetArrangerPlayer.playbackPosition,
                    isPlaying: presetArrangerPlayer.isPlaying,
                    onEditDrumSegment: { segment in
                        editingDrumSegment = segment
                        showingDurationEditor = true
                    },
                    onEditGuitarSegment: { segment in
                        editingGuitarSegment = segment
                        showingDurationEditor = true
                    },
                    onDeleteSegment: { segmentId in
                        deleteSegment(segmentId)
                    }
                )
                .frame(minWidth: 600)

                // 右侧资源面板
                if showingResourcePanel {
                    ArrangementResourcePanel()
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                }
            }

            Divider()

            // 底部控制栏
            HStack {
                Toggle("Resources", isOn: $showingResourcePanel)
                    .toggleStyle(.button)

                Spacer()

                if let segmentId = selectedSegmentId {
                    Button("Delete Selected") {
                        deleteSegment(segmentId)
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingDurationEditor) {
            if let drumSegment = editingDrumSegment {
                DurationEditorView(
                    initialDuration: drumSegment.durationInBeats,
                    onSave: { newDuration in
                        updateDrumSegmentDuration(drumSegment, newDuration: newDuration)
                        editingDrumSegment = nil
                        showingDurationEditor = false
                    },
                    onCancel: {
                        editingDrumSegment = nil
                        showingDurationEditor = false
                    }
                )
            } else if let guitarSegment = editingGuitarSegment {
                DurationEditorView(
                    initialDuration: guitarSegment.durationInBeats,
                    onSave: { newDuration in
                        updateGuitarSegmentDuration(guitarSegment, newDuration: newDuration)
                        editingGuitarSegment = nil
                        showingDurationEditor = false
                    },
                    onCancel: {
                        editingGuitarSegment = nil
                        showingDurationEditor = false
                    }
                )
            }
        }
    }

    private func updateArrangementLength(_ newLength: Double) {
        guard var preset = appData.preset else { return }
        preset.arrangement.updateLength(newLength)
        appData.updateArrangement(preset.arrangement)
    }

    private func deleteSegment(_ segmentId: UUID) {
        guard var preset = appData.preset else { return }
        var arrangement = preset.arrangement

        // 从鼓机轨道删除
        arrangement.drumTrack.segments.removeAll { $0.id == segmentId }

        // 从吉他轨道删除
        for i in 0..<arrangement.guitarTracks.count {
            arrangement.guitarTracks[i].segments.removeAll { $0.id == segmentId }
        }

        appData.updateArrangement(arrangement)
        selectedSegmentId = nil
    }

    private func updateDrumSegmentDuration(_ segment: DrumSegment, newDuration: Double) {
        guard var preset = appData.preset else { return }
        var arrangement = preset.arrangement

        if let index = arrangement.drumTrack.segments.firstIndex(where: { $0.id == segment.id }) {
            arrangement.drumTrack.segments[index].durationInBeats = newDuration
            appData.updateArrangement(arrangement)
        }
    }

    private func updateGuitarSegmentDuration(_ segment: GuitarSegment, newDuration: Double) {
        guard var preset = appData.preset else { return }
        var arrangement = preset.arrangement

        for trackIndex in 0..<arrangement.guitarTracks.count {
            if let segmentIndex = arrangement.guitarTracks[trackIndex].segments.firstIndex(where: { $0.id == segment.id }) {
                arrangement.guitarTracks[trackIndex].segments[segmentIndex].durationInBeats = newDuration
                appData.updateArrangement(arrangement)
                break
            }
        }
    }
}

// MARK: - 工具栏
struct ArrangementToolbar: View {
    let arrangement: SongArrangement
    let isPlaying: Bool
    @Binding var zoomLevel: CGFloat
    let onPlay: () -> Void
    let onUpdateLength: (Double) -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 播放控制
            Button(action: onPlay) {
                HStack {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    Text(isPlaying ? "Stop" : "Play")
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            // 长度控制
            HStack {
                Text("Length:")
                let measures = arrangement.lengthInBeats / 4
                Stepper("\(String(format: "%.0f", measures)) measures",
                       value: Binding(
                           get: { measures },
                           set: { onUpdateLength($0 * 4) }
                       ),
                       in: 4...50,
                       step: 1)
            }

            // 缩放控制
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...3.0)
                    .frame(width: 100)
            }
        }
    }
}

// MARK: - 时间轴视图
struct ArrangementTimelineView: View {
    let arrangement: SongArrangement
    @Binding var selectedSegmentId: UUID?
    let zoomLevel: CGFloat
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let headerHeight: CGFloat
    let playbackPosition: Double
    let isPlaying: Bool
    let onEditDrumSegment: ((DrumSegment) -> Void)?
    let onEditGuitarSegment: ((GuitarSegment) -> Void)?
    let onDeleteSegment: ((UUID) -> Void)?

    @EnvironmentObject var appData: AppData

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(spacing: 2) {
                // 鼓机轨道
                ArrangementDrumTrackView(
                    track: arrangement.drumTrack,
                    arrangement: arrangement,
                    selectedSegmentId: $selectedSegmentId,
                    beatWidth: beatWidth,
                    trackHeight: trackHeight,
                    zoomLevel: zoomLevel,
                    onEditDrumSegment: onEditDrumSegment,
                    onDeleteSegment: onDeleteSegment
                )

                // 吉他轨道
                ForEach(arrangement.guitarTracks) { track in
                    ArrangementGuitarTrackView(
                        track: track,
                        arrangement: arrangement,
                        selectedSegmentId: $selectedSegmentId,
                        beatWidth: beatWidth,
                        trackHeight: trackHeight,
                        zoomLevel: zoomLevel,
                        onEditGuitarSegment: onEditGuitarSegment,
                        onDeleteSegment: onDeleteSegment
                    )
                }
            }
            .frame(width: max(800, beatWidth * CGFloat(arrangement.lengthInBeats) * zoomLevel + 200))
        }
    }
}

// MARK: - 时间标尺
struct ArrangementTimeRuler: View {
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let headerHeight: CGFloat
    let zoomLevel: CGFloat
    let playbackPosition: Double
    let isPlaying: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景和网格
            Canvas { context, size in
                let totalBeats = Int(arrangement.lengthInBeats)
                let beatsPerMeasure = 4 // 简化为4拍

                for beat in 0...totalBeats {
                    let x = CGFloat(beat) * beatWidth * zoomLevel
                    let isMeasureLine = beat % beatsPerMeasure == 0
                    let lineWidth: CGFloat = isMeasureLine ? 2 : 1
                    let opacity = isMeasureLine ? 0.8 : 0.4

                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: headerHeight))

                    context.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: lineWidth)
                }
            }
            .frame(height: headerHeight)

            // 小节号标签
            HStack(spacing: 0) {
                let measureCount = Int(ceil(arrangement.lengthInBeats / 4))
                ForEach(0..<measureCount, id: \.self) { measure in
                    Text("\(measure + 1)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .frame(width: beatWidth * 4 * zoomLevel, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
            .padding(.top, 4)

            // 播放位置指示器
            if isPlaying {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: CGFloat(playbackPosition) * beatWidth * zoomLevel - 1)
                    .frame(height: headerHeight)
            }
        }
    }
}

// MARK: - 鼓机轨道视图
struct ArrangementDrumTrackView: View {
    let track: DrumTrack
    let arrangement: SongArrangement
    @Binding var selectedSegmentId: UUID?
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat
    let onEditDrumSegment: ((DrumSegment) -> Void)?
    let onDeleteSegment: ((UUID) -> Void)?

    @EnvironmentObject var appData: AppData
    @State private var isDragOver: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // 轨道控制
            TrackControlView(
                title: "Drums",
                icon: "drum.fill",
                iconColor: .orange,
                isMuted: track.isMuted
            )
            .frame(width: 120)

            // 时间轴内容
            ZStack(alignment: .topLeading) {
                // 背景
                Rectangle()
                    .fill(Color.orange.opacity(isDragOver ? 0.15 : 0.05))
                    .stroke(isDragOver ? Color.orange : Color.clear, lineWidth: 2)
                    .frame(
                        width: beatWidth * CGFloat(arrangement.lengthInBeats) * zoomLevel,
                        height: trackHeight
                    )

                // 网格线
                TrackGridView(
                    arrangement: arrangement,
                    beatWidth: beatWidth,
                    trackHeight: trackHeight,
                    zoomLevel: zoomLevel
                )

                // 鼓机片段
                ForEach(track.segments) { segment in
                    DrumSegmentView(
                        segment: segment,
                        isSelected: selectedSegmentId == segment.id,
                        beatWidth: beatWidth,
                        trackHeight: trackHeight,
                        zoomLevel: zoomLevel,
                        onEditDuration: onEditDrumSegment,
                        onDelete: { segment in
                            onDeleteSegment?(segment.id)
                        }
                    )
                    .offset(x: CGFloat(segment.startBeat) * beatWidth * zoomLevel)
                    .onTapGesture {
                        selectedSegmentId = segment.id
                    }
                }
            }
            .frame(height: trackHeight)
            .onDrop(of: [.data, .text], delegate: EnhancedDrumTrackDropDelegate(
                track: track,
                arrangement: arrangement,
                beatWidth: beatWidth,
                zoomLevel: zoomLevel,
                isDragOver: $isDragOver,
                appData: appData
            ))
        }
    }
}

// MARK: - 吉他轨道视图
struct ArrangementGuitarTrackView: View {
    let track: GuitarTrack
    let arrangement: SongArrangement
    @Binding var selectedSegmentId: UUID?
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat
    let onEditGuitarSegment: ((GuitarSegment) -> Void)?
    let onDeleteSegment: ((UUID) -> Void)?

    @EnvironmentObject var appData: AppData
    @State private var isDragOver: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // 轨道控制
            TrackControlView(
                title: track.name,
                icon: "guitars",
                iconColor: track.isMuted ? .secondary : .blue,
                isMuted: track.isMuted
            )
            .frame(width: 120)

            // 时间轴内容
            ZStack(alignment: .topLeading) {
                // 背景
                Rectangle()
                    .fill(Color.blue.opacity(isDragOver ? 0.15 : 0.05))
                    .stroke(isDragOver ? Color.blue : Color.clear, lineWidth: 2)
                    .frame(
                        width: beatWidth * CGFloat(arrangement.lengthInBeats) * zoomLevel,
                        height: trackHeight
                    )

                // 网格线
                TrackGridView(
                    arrangement: arrangement,
                    beatWidth: beatWidth,
                    trackHeight: trackHeight,
                    zoomLevel: zoomLevel
                )

                // 吉他片段
                ForEach(track.segments) { segment in
                    GuitarSegmentView(
                        segment: segment,
                        isSelected: selectedSegmentId == segment.id,
                        beatWidth: beatWidth,
                        trackHeight: trackHeight,
                        zoomLevel: zoomLevel,
                        onEditDuration: onEditGuitarSegment,
                        onDelete: { segment in
                            onDeleteSegment?(segment.id)
                        }
                    )
                    .offset(x: CGFloat(segment.startBeat) * beatWidth * zoomLevel)
                    .onTapGesture {
                        selectedSegmentId = segment.id
                    }
                }
            }
            .frame(height: trackHeight)
            .onDrop(of: [.data, .text], delegate: EnhancedGuitarTrackDropDelegate(
                track: track,
                arrangement: arrangement,
                beatWidth: beatWidth,
                zoomLevel: zoomLevel,
                isDragOver: $isDragOver,
                appData: appData
            ))
        }
    }
}

// MARK: - 轨道控制视图
struct TrackControlView: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .strikethrough(isMuted)

                if isMuted {
                    Text("Muted")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - 网格视图
struct TrackGridView: View {
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat

    var body: some View {
        Canvas { context, size in
            let totalBeats = Int(arrangement.lengthInBeats)
            let beatsPerMeasure = 4

            for beat in 0...totalBeats {
                let x = CGFloat(beat) * beatWidth * zoomLevel
                let isMeasureLine = beat % beatsPerMeasure == 0
                let lineWidth: CGFloat = isMeasureLine ? 1.5 : 0.5
                let opacity = isMeasureLine ? 0.4 : 0.2

                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: trackHeight))

                context.stroke(path, with: .color(.primary.opacity(opacity)), lineWidth: lineWidth)
            }
        }
    }
}

// MARK: - 资源面板
struct ArrangementResourcePanel: View {
    @EnvironmentObject var appData: AppData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resources")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 鼓机节奏
                    ResourceSection(title: "Drum Patterns", icon: "drum.fill") {
                        if let patterns = appData.preset?.drumPatterns, !patterns.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                                ForEach(patterns) { pattern in
                                    DrumPatternResourceButton(pattern: pattern)
                                }
                            }
                        } else {
                            Text("No drum patterns available")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }

                    // Solo片段
                    ResourceSection(title: "Solo Segments", icon: "music.note.list") {
                        if let solos = appData.preset?.soloSegments, !solos.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                                ForEach(solos) { solo in
                                    SoloResourceButton(segment: solo)
                                }
                            }
                        } else {
                            Text("No solo segments available")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }

                    // 伴奏片段
                    ResourceSection(title: "Accompaniment", icon: "guitars.fill") {
                        if let accompaniments = appData.preset?.accompanimentSegments, !accompaniments.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                                ForEach(accompaniments) { acc in
                                    AccompanimentResourceButton(segment: acc)
                                }
                            }
                        } else {
                            Text("No accompaniment segments available")
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct ResourceSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.headline)
            }
            .foregroundColor(.primary)

            content
        }
    }
}

// MARK: - Duration Editor
struct DurationEditorView: View {
    let initialDuration: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var durationInBeats: Double
    @State private var durationText: String

    init(initialDuration: Double, onSave: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.initialDuration = initialDuration
        self.onSave = onSave
        self.onCancel = onCancel
        self._durationInBeats = State(initialValue: initialDuration)
        self._durationText = State(initialValue: String(format: "%.1f", initialDuration))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Segment Duration")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Duration (beats):")
                    .font(.headline)

                TextField("Duration", text: $durationText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let value = Double(durationText), value > 0 {
                            durationInBeats = value
                        } else {
                            durationText = String(format: "%.1f", durationInBeats)
                        }
                    }

                Stepper("", value: $durationInBeats, in: 0.25...32, step: 0.25)
                    .onChange(of: durationInBeats) { _, newValue in
                        durationText = String(format: "%.1f", newValue)
                    }

                Text("Current: \(String(format: "%.1f", durationInBeats)) beats")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }

                Button("Save") {
                    onSave(durationInBeats)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}