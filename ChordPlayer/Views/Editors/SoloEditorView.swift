import SwiftUI

struct SoloEditorView: View {
    @Binding var soloSegment: SoloSegment
    @State private var selectedNotes: Set<UUID> = []
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var currentFret: Int = 0
    @State private var gridSize: Double = 0.25 // 四分音符网格
    @State private var zoomLevel: CGFloat = 1.0
    @State private var isPlaying: Bool = false
    @State private var playbackPosition: Double = 0
    
    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let beatWidth: CGFloat = 80
    private let stringHeight: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            SoloToolbar(
                currentTechnique: $currentTechnique,
                currentFret: $currentFret,
                gridSize: $gridSize,
                zoomLevel: $zoomLevel,
                isPlaying: $isPlaying,
                playbackPosition: $playbackPosition,
                onPlay: playToggle,
                onStop: stop
            )
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 主编辑区域
            ScrollView([.horizontal, .vertical]) {
                SoloTablatureView(
                    soloSegment: $soloSegment,
                    selectedNotes: $selectedNotes,
                    currentTechnique: currentTechnique,
                    currentFret: currentFret,
                    gridSize: gridSize,
                    zoomLevel: zoomLevel,
                    playbackPosition: playbackPosition,
                    beatWidth: beatWidth,
                    stringHeight: stringHeight,
                    onNoteAdd: addNote,
                    onNoteSelect: selectNote,
                    onNoteDelete: deleteSelectedNotes,
                    onDeselectAll: deselectAllNotes
                )
                .frame(
                    width: max(600, beatWidth * CGFloat(soloSegment.lengthInBeats) * zoomLevel),
                    height: stringHeight * 6 + 100
                )
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // 底部信息栏
            HStack {
                Text("Selected: \(selectedNotes.count) notes")
                Spacer()
                Text("Length: \(String(format: "%.1f", soloSegment.lengthInBeats)) beats")
                Spacer()
                Text("Notes: \(soloSegment.notes.count)")
            }
            .padding(.horizontal)
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onKeyDown { event in
            handleKeyDown(event)
        }
        .onChange(of: selectedNotes) {
            // 当选择的音符变为一个时，用它的属性更新工具栏
            if selectedNotes.count == 1, let selectedNote = soloSegment.notes.first(where: { $0.id == selectedNotes.first! }) {
                currentFret = selectedNote.fret
                currentTechnique = selectedNote.technique
            }
        }
        .onChange(of: currentFret) { 
            updateSelectedNote { $0.fret = currentFret }
        }
        .onChange(of: currentTechnique) { 
            updateSelectedNote { $0.technique = currentTechnique }
        }
    }
    
    private func updateSelectedNote(change: (inout SoloNote) -> Void) {
        if selectedNotes.count == 1, let index = soloSegment.notes.firstIndex(where: { $0.id == selectedNotes.first! }) {
            change(&soloSegment.notes[index])
        }
    }
    
    private func addNote(at position: CGPoint) {
        let stringLabelWidth: CGFloat = 30.0
        let string = Int(position.y / stringHeight)
        let time = Double((position.x - stringLabelWidth) / beatWidth) / Double(zoomLevel)
        
        guard string >= 0 && string < 6 && time >= 0 && time <= soloSegment.lengthInBeats else { return }
        
        // 对齐到网格
        let alignedTime = snapToGrid(time)
        
        let newNote = SoloNote(
            startTime: alignedTime,
            string: string,
            fret: currentFret,
            technique: currentTechnique
        )
        
        soloSegment.notes.append(newNote)
        selectedNotes = [newNote.id]
    }
    
    private func selectNote(_ noteId: UUID, addToSelection: Bool = false) {
        if addToSelection {
            if selectedNotes.contains(noteId) {
                selectedNotes.remove(noteId)
            } else {
                selectedNotes.insert(noteId)
            }
        } else {
            selectedNotes = [noteId]
        }
    }
    
    private func deselectAllNotes() {
        selectedNotes.removeAll()
    }
    
    private func deleteSelectedNotes() {
        soloSegment.notes.removeAll { selectedNotes.contains($0.id) }
        selectedNotes.removeAll()
    }
    
    private func snapToGrid(_ time: Double) -> Double {
        return round(time / gridSize) * gridSize
    }
    
    private func playToggle() {
        isPlaying.toggle()
        if isPlaying {
            // TODO: 实现播放逻辑
        }
    }
    
    private func stop() {
        isPlaying = false
        playbackPosition = 0
    }
    
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 51: // Delete key
            deleteSelectedNotes()
            return true
        case 49: // Space key
            playToggle()
            return true
        default:
            return false
        }
    }
}

struct SoloToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var currentFret: Int
    @Binding var gridSize: Double
    @Binding var zoomLevel: CGFloat
    @Binding var isPlaying: Bool
    @Binding var playbackPosition: Double
    
    let onPlay: () -> Void
    let onStop: () -> Void
    
    private let durations: [(String, Double)] = [
        ("1/1", 1.0), ("1/2", 0.5), ("1/4", 0.25), ("1/8", 0.125), ("1/16", 0.0625)
    ]
    
    var body: some View {
        HStack(spacing: 20) {
            // --- Group 1: Playback Controls ---
            HStack {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            // --- Group 2: Note Properties ---
            HStack(spacing: 15) {
                Picker("Technique", selection: $currentTechnique) {
                    ForEach(PlayingTechnique.allCases) { technique in
                        Text(technique.symbol.isEmpty ? technique.rawValue : technique.symbol).tag(technique)
                    }
                }
                .frame(minWidth: 80)
                .help("Playing Technique")

                HStack(spacing: 4) {
                    Image(systemName: "number")
                    TextField("Fret", value: $currentFret, format: .number)
                        .frame(width: 40)
                }
                .help("Fret Number")
            }

            Spacer()

            // --- Group 3: Canvas Controls ---
            HStack(spacing: 15) {
                Picker("Grid", selection: $gridSize) {
                    ForEach(durations, id: \.1) { name, value in
                        Label(name, systemImage: "squareshape.split.2x2").tag(value)
                    }
                }
                .frame(minWidth: 80)
                .help("Grid Snap")
                
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Slider(value: $zoomLevel, in: 0.5...3.0)
                        .frame(width: 100)
                }
                .help("Zoom Level")
            }
        }
        .textFieldStyle(.roundedBorder)
        .pickerStyle(.menu)
    }
}

struct SoloTablatureView: View {
    @Binding var soloSegment: SoloSegment
    @Binding var selectedNotes: Set<UUID>
    
    let currentTechnique: PlayingTechnique
    let currentFret: Int
    let gridSize: Double
    let zoomLevel: CGFloat
    let playbackPosition: Double
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    
    let onNoteAdd: (CGPoint) -> Void
    let onNoteSelect: (UUID, Bool) -> Void
    let onNoteDelete: () -> Void
    let onDeselectAll: () -> Void
    
    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // 背景网格
            SoloGridView(
                lengthInBeats: soloSegment.lengthInBeats,
                gridSize: gridSize,
                beatWidth: beatWidth,
                stringHeight: stringHeight,
                zoomLevel: zoomLevel
            )
            
            // 弦线
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { stringIndex in
                    SoloStringLineView(
                        stringIndex: stringIndex,
                        stringName: stringNames[stringIndex],
                        lengthInBeats: soloSegment.lengthInBeats,
                        beatWidth: beatWidth,
                        stringHeight: stringHeight,
                        zoomLevel: zoomLevel
                    )
                }
            }
            
            // 音符
            ForEach(soloSegment.notes) { note in
                SoloNoteView(
                    note: note,
                    isSelected: selectedNotes.contains(note.id),
                    beatWidth: beatWidth,
                    stringHeight: stringHeight,
                    zoomLevel: zoomLevel,
                    onSelect: { addToSelection in
                        onNoteSelect(note.id, addToSelection)
                    }
                )
            }
            
            // 播放位置指示器
            if playbackPosition > 0 {
                let stringLabelWidth: CGFloat = 30.0
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .position(x: stringLabelWidth + CGFloat(playbackPosition) * beatWidth * zoomLevel, y: stringHeight * 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            onNoteAdd(location)
        }
        .onTapGesture(count: 1) {
            onDeselectAll()
        }
    }
}

struct SoloGridView: View {
    let lengthInBeats: Double
    let gridSize: Double
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    let zoomLevel: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let stringLabelWidth: CGFloat = 30.0
            let totalWidth = beatWidth * CGFloat(lengthInBeats) * zoomLevel
            let totalHeight = stringHeight * 6
            
            // 垂直网格线
            var beat = 0.0
            while beat <= lengthInBeats {
                let x = stringLabelWidth + CGFloat(beat) * beatWidth * zoomLevel
                let isMainBeat = beat.truncatingRemainder(dividingBy: 1.0) == 0
                
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: totalHeight))
                    },
                    with: .color(isMainBeat ? .secondary : .secondary.opacity(0.5)),
                    lineWidth: isMainBeat ? 1 : 0.5
                )
                
                beat += gridSize
            }
        }
    }
}

struct SoloStringLineView: View {
    let stringIndex: Int
    let stringName: String
    let lengthInBeats: Double
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    let zoomLevel: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            // 弦名标签
            Text(stringName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: stringHeight)
                .background(Color(NSColor.controlBackgroundColor))
            
            // 弦线
            Rectangle()
                .fill(Color.primary)
                .frame(width: beatWidth * CGFloat(lengthInBeats) * zoomLevel, height: 1)
                .frame(height: stringHeight)
        }
    }
}

struct SoloNoteView: View {
    let note: SoloNote
    let isSelected: Bool
    let beatWidth: CGFloat
    let stringHeight: CGFloat
    let zoomLevel: CGFloat
    let onSelect: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            // 品位数字
            Text("\(note.fret)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        .overlay(Circle().stroke(Color.primary, lineWidth: 1))
                )
            
            // 技巧标记
            if !note.technique.symbol.isEmpty {
                Text(note.technique.symbol)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .position(
            x: 30 + CGFloat(note.startTime) * beatWidth * zoomLevel,
            y: CGFloat(note.string) * stringHeight + stringHeight / 2
        )
        .onTapGesture {
            onSelect(false)
        }
    }
}

// 辅助扩展
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Bool) -> some View {
        self.background(KeyEventHandlingView(onKeyDown: action))
    }
}

struct KeyEventHandlingView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyEventView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyEventView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
}