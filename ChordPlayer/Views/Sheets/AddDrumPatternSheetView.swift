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
    // 1. Add distinct colors for each instrument
    private let instrumentColors: [Color] = [.red.opacity(0.8), .orange.opacity(0.8), .yellow.opacity(0.8)]

    let editingPatternData: DrumPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    init(editingPatternData: DrumPatternEditorData? = nil) {
        self.editingPatternData = editingPatternData
        _gridState = State(initialValue: Array(repeating: Array(repeating: false, count: 16), count: 3))
    }

    var body: some View {
        // 2. Reduce vertical spacing for a more compact layout
        VStack(spacing: 12) {
            headerView
                .padding(.horizontal)
                .padding(.top, 16)
            
            Divider()
            
            toolbarView
                .padding(.horizontal)
            
            // 3. Remove horizontal scroll and use dynamic sizing
            gridEditorView
                .padding(.horizontal)
                .padding(.bottom, 8)

            Spacer()
            
            Divider()
            
            footerButtons
                .padding()
        }
        .frame(minWidth: 680, idealWidth: 750, minHeight: 480, idealHeight: 520) // Adjusted frame
        .background(Color(.windowBackgroundColor))
        .onAppear(perform: setupInitialState)
        .onDisappear {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            }
        }
        .onChange(of: timeSignature) { updateGridSize() }
        .onChange(of: subdivision) { updateGridSize() }
    }

    private var headerView: some View {
        HStack {
            Text(isEditing ? "编辑鼓点模式" : "创建新鼓点模式")
                .font(.system(size: 22, weight: .bold))
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(instrumentNames, id: \.self) { name in
                    Text(name)
                        .font(.headline)
                        .frame(height: 35, alignment: .leading) // Dynamic height
                }
            }
            .frame(width: 60)
            
            // Use GeometryReader to calculate cell width dynamically
            GeometryReader { geometry in
                let numberOfSteps = gridState[0].count
                let totalSpacing = CGFloat(numberOfSteps - 1) * 2 // Spacing between cells
                let stepWidth = (geometry.size.width - totalSpacing) / CGFloat(numberOfSteps)

                HStack(spacing: 2) {
                    let stepsPerBeat = subdivision == 8 ? 2 : 4
                    
                    ForEach(0..<numberOfSteps, id: \.self) { col in
                        VStack(spacing: 2) {
                            ForEach(0..<instruments.count, id: \.self) { row in
                                gridCell(row: row, col: col, size: stepWidth)
                            }
                        }
                        .background(
                            (col / stepsPerBeat) % 2 == 0 ? Color.clear : Color.secondary.opacity(0.1)
                        )
                        
                        if (col + 1) % stepsPerBeat == 0 && col < numberOfSteps - 1 {
                            Divider()
                        }
                    }
                }
                .overlay(playbackIndicator(stepWidth: stepWidth, spacing: 2))
            }
        }
    }
    
    private func gridCell(row: Int, col: Int, size: CGFloat) -> some View {
        let isActive = gridState[row][col]
        
        return RoundedRectangle(cornerRadius: 4)
            // Use instrument-specific color
            .fill(isActive ? instrumentColors[row] : Color.primary.opacity(0.2))
            .frame(width: size, height: 35) // Use dynamic width
            .onTapGesture {
                gridState[row][col].toggle()
                if gridState[row][col] {
                    drumPlayer.playNote(midiNumber: instruments[row])
                }
            }
    }
    
    private func playbackIndicator(stepWidth: CGFloat, spacing: CGFloat) -> some View {
        GeometryReader { geometry in
            if let currentStep = drumPlayer.currentPreviewStep, drumPlayer.isPlaying {
                let position = (CGFloat(currentStep) * (stepWidth + spacing)) + (stepWidth / 2)
                Rectangle()
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: position)
                    .animation(.linear(duration: 0.05), value: drumPlayer.currentPreviewStep)
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
            updateGridSize()
        }
    }
    
    private func updateGridSize() {
        let timeParts = timeSignature.split(separator: "/").map(String.init)
        let numerator = Double(timeParts.first ?? "4") ?? 4.0
        let denominator = Double(timeParts.last ?? "4") ?? 4.0
        let columns = Int((numerator / denominator) * Double(subdivision))
        
        var newGrid = Array(repeating: Array(repeating: false, count: columns), count: instruments.count)
        let oldColumns = gridState[0].count
        let minColumns = min(oldColumns, columns)
        
        if minColumns > 0 {
            for r in 0..<instruments.count {
                for c in 0..<minColumns {
                    newGrid[r][c] = gridState[r][c]
                }
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
        
        if !isEditing {
            self.id = "CUSTOM_\(UUID().uuidString)"
        }
        
        guard !id.isEmpty, !displayName.isEmpty else {
            print("ID and Display Name cannot be empty.")
            return
        }
        
        let newPattern = buildPatternFromGrid()
        customDrumPatternManager.addOrUpdatePattern(id: id, timeSignature: timeSignature, pattern: newPattern)
        
        dismiss()
    }
}