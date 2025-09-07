import SwiftUI

struct AddDrumPatternSheetView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager

    // State for the form fields
    @State private var id: String = ""
    @State private var displayName: String = ""
    @State private var timeSignature: String = "4/4"
    @State private var subdivision: Int = 8 // 8th notes
    
    // Represents the visual grid state. E.g., [instrument_index][time_step]
    @State private var gridState: [[Bool]] = Array(repeating: Array(repeating: false, count: 8), count: 3)

    // MIDI notes for Kick, Snare, Hi-Hat
    private let instruments: [Int] = [36, 38, 42]
    private let instrumentNames: [String] = ["Kick", "Snare", "Hi-Hat"]
    
    let editingPatternData: DrumPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    init(editingPatternData: DrumPatternEditorData? = nil) {
        self.editingPatternData = editingPatternData
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ScrollView {
                VStack(spacing: 20) {
                    formView
                    Divider()
                    gridEditorView
                }
                .padding()
            }
            
            Divider()
            footerButtons
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500)
        .onAppear(perform: setupInitialState)
        .onChange(of: timeSignature) { _ in updateGridSize() }
        .onChange(of: subdivision) { _ in updateGridSize() }
    }

    private var headerView: some View {
        Text(isEditing ? "编辑鼓点模式" : "创建新鼓点模式")
            .font(.largeTitle)
            .fontWeight(.bold)
            .padding()
    }

    private var formView: some View {
        Form {
            TextField("唯一ID (例如 ROCK_NEW)", text: $id)
                .disabled(isEditing)
            TextField("显示名称 (例如 新摇滚节奏)", text: $displayName)
            
            Picker("拍子", selection: $timeSignature) {
                Text("4/4").tag("4/4")
                Text("3/4").tag("3/4")
                Text("6/8").tag("6/8")
            }
            
            Picker("精度", selection: $subdivision) {
                Text("8分音符").tag(8)
                Text("16分音符").tag(16)
            }
        }
        .padding(.bottom)
    }

    private var gridEditorView: some View {
        VStack {
            HStack(spacing: 0) {
                // Instrument names column
                VStack(alignment: .leading) {
                    ForEach(instrumentNames, id: \.self) {
                        Text($0).frame(width: 80, height: 40, alignment: .leading).padding(.leading)
                    }
                }
                
                // Grid columns
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<gridState[0].count, id: \.self) { col in
                            VStack(spacing: 0) {
                                ForEach(0..<instruments.count, id: \.self) { row in
                                    gridCell(row: row, col: col)
                                }
                            }
                            if (col + 1) % (subdivision == 8 ? 2 : 4) == 0 {
                                Divider().background(Color.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func gridCell(row: Int, col: Int) -> some View {
        Rectangle()
            .fill(gridState[row][col] ? Color.accentColor : Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .border(Color.black.opacity(0.1))
            .onTapGesture {
                gridState[row][col].toggle()
            }
    }

    private var footerButtons: some View {
        HStack {
            Button("取消", role: .cancel) { dismiss() }
            Spacer()
            Button("保存", action: save)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func setupInitialState() {
        if let data = editingPatternData {
            self.id = data.id
            self.displayName = data.pattern.displayName
            self.timeSignature = data.timeSignature
            // This is a simplification. A robust solution would parse the delay string.
            if let firstEvent = data.pattern.pattern.first, firstEvent.delay.contains("16") {
                self.subdivision = 16
            } else {
                self.subdivision = 8
            }
            // This is a placeholder. A real implementation needs to convert pattern events to grid state.
            updateGridSize()
        }
    }
    
    private func updateGridSize() {
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let columns = beats * (subdivision == 8 ? 2 : 4)
        gridState = Array(repeating: Array(repeating: false, count: columns), count: instruments.count)
    }

    private func save() {
        // 1. Convert the visual grid state into a valid [DrumPatternEvent] array.
        var patternEvents: [DrumPatternEvent] = []
        var lastEventTime: Double = 0.0
        let timePerStep = 1.0 / Double(subdivision)

        for col in 0..<gridState[0].count {
            let notesForThisStep: [Int] = instruments.indices.compactMap { row in
                gridState[row][col] ? instruments[row] : nil
            }

            if !notesForThisStep.isEmpty {
                let eventTime = Double(col) * timePerStep
                let delayValue = eventTime - lastEventTime
                
                // The delay is a fraction of a whole note. Assuming 4/4 time, a whole note is 4 beats.
                // For now, we use a simplified delay string based on subdivision.
                // A more robust solution would use GCD to find the simplest fraction.
                let delayNumerator = Int(round(delayValue * Double(subdivision)))
                let delayString = "\(delayNumerator)/\(subdivision)"

                patternEvents.append(DrumPatternEvent(delay: delayString, notes: notesForThisStep))
                lastEventTime = eventTime
            }
        }

        // 2. Create the DrumPattern object.
        let newPattern = DrumPattern(displayName: displayName, pattern: patternEvents)
        
        // 3. Save using the manager.
        customDrumPatternManager.addOrUpdatePattern(id: id, timeSignature: timeSignature, pattern: newPattern)
        
        // 4. Dismiss the sheet.
        dismiss()
    }
}