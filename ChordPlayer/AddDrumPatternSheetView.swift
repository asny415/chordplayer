import SwiftUI

struct AddDrumPatternSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager
    @EnvironmentObject var drumPlayer: DrumPlayer

    // Form state
    @State private var id: String = ""
    @State private var displayName: String = ""
    @State private var timeSignature: String = "4/4"
    @State private var subdivision: Int = 16
    @State private var bpm: Double = 120.0
    
    @State private var gridState: [[Bool]]
    
    private let instruments: [Int] = [36, 38, 42] // MIDI notes for Kick, Snare, Hi-Hat
    private let instrumentNames: [String] = ["Kick", "Snare", "Hi-Hat"]
    
    let editingPatternData: DrumPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    init(editingPatternData: DrumPatternEditorData? = nil) {
        self.editingPatternData = editingPatternData
        // Initialize gridState here to avoid "cannot use instance member within property initializer"
        _gridState = State(initialValue: Array(repeating: Array(repeating: false, count: 16), count: 3))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Divider()
            
            toolbarView
                .padding()
            
            gridEditorView
                .padding(.horizontal)

            Spacer()
            
            Divider()
            
            footerButtons
                .padding()
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 550)
        .background(Color(.windowBackgroundColor))
        .onAppear(perform: setupInitialState)
        .onDisappear {
            // Ensure playback stops when the view is closed
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            }
        }
        .onChange(of: timeSignature) { _ in updateGridSize() }
        .onChange(of: subdivision) { _ in updateGridSize() }
    }

    private var headerView: some View {
        HStack {
            Text(isEditing ? "编辑鼓点模式" : "创建新鼓点模式")
                .font(.system(size: 24, weight: .bold))
            Spacer()
            TextField("显示名称 (例如: Funky Beat)", text: $displayName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: 250)
        }
    }

    private var toolbarView: some View {
        HStack(spacing: 20) {
            Picker("拍子:", selection: $timeSignature) {
                Text("4/4").tag("4/4")
                Text("3/4").tag("3/4")
                Text("6/8").tag("6/8")
            }
            .pickerStyle(MenuPickerStyle())
            
            Picker("精度:", selection: $subdivision) {
                Text("8分音符").tag(8)
                Text("16分音符").tag(16)
            }
            .pickerStyle(MenuPickerStyle())
            
            Spacer()
            
            HStack {
                Text("BPM:")
                Stepper(value: $bpm, in: 40...240, step: 1) {
                    Text("\(Int(bpm))")
                }
            }
        }
    }

    private var gridEditorView: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(instrumentNames, id: \.self) { name in
                    Text(name)
                        .font(.headline)
                        .frame(width: 80, height: 44, alignment: .leading)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
                    let stepsPerBeat = subdivision == 8 ? 2 : 4
                    
                    ForEach(0..<gridState[0].count, id: \.self) { col in
                        VStack(spacing: 0) {
                            ForEach(0..<instruments.count, id: \.self) { row in
                                gridCell(row: row, col: col)
                            }
                        }
                        .background(
                            (col / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1)
                        )
                        
                        if (col + 1) % stepsPerBeat == 0 && col < gridState[0].count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.top, 4) // Padding to allow for playback indicator
                .overlay(playbackIndicator)
            }
        }
    }
    
    private func gridCell(row: Int, col: Int) -> some View {
        let isActive = gridState[row][col]
        
        return RoundedRectangle(cornerRadius: 5)
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.2))
            .frame(width: 40, height: 40)
            .padding(2)
            .onTapGesture {
                gridState[row][col].toggle()
                // Play sound on tap if the note is being turned on
                if gridState[row][col] {
                    drumPlayer.playNote(midiNumber: instruments[row])
                }
            }
    }
    
    private var playbackIndicator: some View {
        GeometryReader { geometry in
            if let currentStep = drumPlayer.currentStep, drumPlayer.isPlaying {
                let stepWidth = geometry.size.width / CGFloat(gridState[0].count)
                Rectangle()
                    .fill(Color.red.opacity(0.7))
                    .frame(width: 2)
                    .offset(x: (CGFloat(currentStep) + 0.5) * stepWidth)
                    .animation(.linear(duration: 0.05), value: drumPlayer.currentStep)
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("取消", role: .cancel) { dismiss() }
            
            Spacer()
            
            Button(action: togglePlayback) {
                Image(systemName: drumPlayer.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
            }
            .frame(width: 50)
            
            Spacer()

            Button("保存", action: save)
                .buttonStyle(.borderedProminent)
        }
    }
    
    private func setupInitialState() {
        if let data = editingPatternData {
            self.id = data.id
            self.displayName = data.pattern.displayName
            self.timeSignature = data.timeSignature
            
            let (parsedGrid, parsedSubdivision) = DrumPattern.toGrid(
                pattern: data.pattern,
                timeSignature: data.timeSignature,
                instruments: instruments
            )
            self.gridState = parsedGrid
            self.subdivision = parsedSubdivision
            
        } else {
            // For new patterns, just ensure the grid size is correct
            updateGridSize()
        }
    }
    
    private func updateGridSize() {
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let columns = beats * (subdivision == 8 ? 2 : 4)
        
        // Preserve existing pattern when resizing
        var newGrid = Array(repeating: Array(repeating: false, count: columns), count: instruments.count)
        let oldColumns = gridState[0].count
        let minColumns = min(oldColumns, columns)
        
        for r in 0..<instruments.count {
            for c in 0..<minColumns {
                newGrid[r][c] = gridState[r][c]
            }
        }
        gridState = newGrid
    }
    
    private func buildPatternFromGrid() -> DrumPattern {
        let patternEvents = DrumPattern.fromGrid(
            grid: gridState,
            subdivision: subdivision,
            instruments: instruments
        )
        return DrumPattern(displayName: displayName, pattern: patternEvents)
    }

    private func togglePlayback() {
        if drumPlayer.isPlaying {
            drumPlayer.stop()
        } else {
            let patternToPlay = buildPatternFromGrid()
            drumPlayer.play(drumPattern: patternToPlay, timeSignature: timeSignature, bpm: bpm)
        }
    }

    private func save() {
        if drumPlayer.isPlaying {
            drumPlayer.stop()
        }
        
        // If it's a new pattern, generate a unique ID
        if !isEditing {
            self.id = "CUSTOM_\(UUID().uuidString)"
        }
        
        guard !id.isEmpty, !displayName.isEmpty else {
            // Optional: Show an alert to the user
            print("ID and Display Name cannot be empty.")
            return
        }
        
        let newPattern = buildPatternFromGrid()
        customDrumPatternManager.addOrUpdatePattern(id: id, timeSignature: timeSignature, pattern: newPattern)
        
        dismiss()
    }
}
