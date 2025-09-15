import SwiftUI

struct PlayingPatternEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var appData: AppData

    // Alert state
    @State private var showNameConflictAlert = false

    // Form state
    @State private var id: String
    @State private var name: String
    @State private var timeSignature: String
    @State private var subdivision: Int

    // Grid state
    private let stringCount = 6
    @State private var grid: [[Bool]]
    @State private var markers: [[String?]]
    
    @State private var strumDirections: [String?]
    @State private var strumStart: (col: Int, string: Int)? = nil

    let editingPatternData: PlayingPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    init(editingPatternData: PlayingPatternEditorData? = nil, globalTimeSignature: String? = nil) {
        self.editingPatternData = editingPatternData

        var initialId = UUID().uuidString
        var initialName = "新演奏模式"
        var initialTimeSignature: String
        var initialSubdivision = 8

        if let data = editingPatternData {
            initialId = data.id
            initialName = data.pattern.name
            initialTimeSignature = data.timeSignature
            if let firstEvent = data.pattern.pattern.first,
               let denominator = Int(firstEvent.delay.split(separator: "/").last ?? "8") {
                initialSubdivision = (denominator == 16) ? 16 : 8
            }
        } else {
            initialTimeSignature = globalTimeSignature ?? "4/4"
        }
        

        _id = State(initialValue: initialId)
        _name = State(initialValue: initialName)
        _timeSignature = State(initialValue: initialTimeSignature)
        _subdivision = State(initialValue: initialSubdivision)
        

        let timeParts = initialTimeSignature.split(separator: "/").map(String.init)
        let numerator = Double(timeParts.first ?? "4") ?? 4.0
        let denominator = Double(timeParts.last ?? "4") ?? 4.0
        let cols = Int((numerator / denominator) * Double(initialSubdivision))
        var initialGrid = Array(repeating: Array(repeating: false, count: cols), count: 6)
        var initialMarkers: [[String?]] = Array(repeating: Array(repeating: nil, count: cols), count: 6)
        var initialStrumDirections: [String?] = Array(repeating: nil, count: cols)

        if let data = editingPatternData, cols > 0 {
            for event in data.pattern.pattern {
                if let delayFraction = MusicTheory.parsePatternDelay(event.delay) {
                    let col = Int(round(delayFraction * Double(initialSubdivision)))
                    let safeCol = max(0, min(cols - 1, col))
                    let isStrum = (event.delta ?? 0) > 0
                    if isStrum {
                        let intNotes = event.notes.compactMap { note -> Int? in
                            if case .chordString(let v) = note { return v }
                            return nil
                        }
                        if !intNotes.isEmpty {
                            for n in intNotes { if (1...6).contains(n) { initialGrid[n-1][safeCol] = true } }
                            if let first = intNotes.first, let last = intNotes.last {
                                initialStrumDirections[safeCol] = (first > last) ? "up" : "down"
                            }
                        }
                    } else {
                        for note in event.notes {
                            switch note {
                            case .chordString(let v):
                                if (1...6).contains(v) { initialGrid[v-1][safeCol] = true }
                            case .chordRoot:
                                let idx = min(4, 6-1)
                                initialMarkers[idx][safeCol] = "ROOT"
                                initialGrid[idx][safeCol] = true
                            case .specificFret(let string, let fret):
                                if (1...6).contains(string) {
                                    initialGrid[string-1][safeCol] = true
                                    initialMarkers[string-1][safeCol] = "FRET:\(fret)"
                                }
                            }
                        }
                    }
                }
            }
        }
        
        _grid = State(initialValue: initialGrid)
        _markers = State(initialValue: initialMarkers)
        _strumDirections = State(initialValue: initialStrumDirections)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "编辑演奏模式" : "创建新演奏模式")
                .font(.title).fontWeight(.semibold).padding()

            ScrollView([.vertical]) {
                VStack(spacing: 12) {
                    // --- Top form ---
                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("名称:")
                                TextField("显示名称", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 320)
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("拍子:")
                                Text(timeSignature)
                                    .padding(.horizontal, 8)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            Picker("细分", selection: $subdivision) {
                                Text("8分音符").tag(8)
                                Text("16分音符").tag(16)
                            }
                            .pickerStyle(.segmented).frame(width: 200)
                        }
                    }
                    .padding(.horizontal)

                    // --- Mode toggle ---
                    HStack {
                        Spacer()
                        Button("预览整和弦 (C)") { previewChordC() }
                    }
                    .padding(.horizontal)

                    Divider()

                    VStack(spacing: 8) {
                        combinedGridArea()
                        Text("提示：点击格子预览单音；右键(或长按)设置演奏方式")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical)
                }
            }

            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 560)
        
        .onChange(of: timeSignature) { updateGridSize() }
        .onChange(of: subdivision) { updateGridSize() }
        .onChange(of: grid) { updateSmartName() }
        .onChange(of: markers) { updateSmartName() }
        
        .onChange(of: strumDirections) { updateSmartName() }
        .alert("名称已存在", isPresented: $showNameConflictAlert) {
            Button("好的") { }
        } message: {
            Text("已存在一个具有相同名称的演奏模式。请输入一个不同的名称。")
        }
    }

    // MARK: - Views
    private func combinedGridArea() -> some View {
        let cols = grid.first?.count ?? 8
        let labelWidth: CGFloat = 44
        let spacing: CGFloat = 6

        return ScrollView(.vertical) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let endPadding: CGFloat = 16
                let totalSpacing = CGFloat(max(0, cols - 1)) * spacing + endPadding
                let availableForCells = max(40, totalWidth - labelWidth - totalSpacing - 16)
                let rawCell = availableForCells / CGFloat(max(1, cols))
                let minCell: CGFloat = subdivision == 8 ? 28 : 20
                let maxCell: CGFloat = subdivision == 8 ? 44 : 36
                let computedCellWidth = min(maxCell, max(minCell, floor(rawCell)))
                let contentWidth = labelWidth + CGFloat(cols) * computedCellWidth + CGFloat(max(0, cols - 1)) * spacing + 16

                HStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 6) {
                        // Header row with DOWN buttons
                        HStack(spacing: spacing) {
                            Spacer().frame(width: labelWidth)
                            ForEach(0..<cols, id: \.self) { col in
                                Button(action: { toggleStrumDirection(for: col, direction: "down") }) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.title3)
                                        .foregroundColor(strumDirections[safe: col] == "down" ? .accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: computedCellWidth, height: 28)
                            }
                            Spacer().frame(width: 8)
                        }

                        // Grid rows
                        ForEach(0..<stringCount, id: \.self) { stringIndex in
                            HStack(spacing: spacing) {
                                Text("弦 \(stringIndex + 1)")
                                    .frame(width: labelWidth, alignment: .trailing)
                                    .font(.subheadline)

                                ForEach(0..<cols, id: \.self) { col in
                                    ZStack {
                                        Rectangle()
                                            .fill(grid[stringIndex][col] ? Color.accentColor.opacity(0.9) : Color.gray.opacity(0.12))
                                            .frame(width: computedCellWidth, height: 36)
                                            .cornerRadius(6)
                                            .contentShape(Rectangle())
                                            .onTapGesture { toggleCell(string: stringIndex, col: col) }
                                            .contextMenu {
                                                Button("设置为 ROOT") { 
                                                    markers[stringIndex][col] = "ROOT"
                                                    grid[stringIndex][col] = true
                                                }
                                                Button("设置为 固定弦") { 
                                                    markers[stringIndex][col] = "FIXED:\(stringIndex+1)"
                                                    grid[stringIndex][col] = true
                                                }
                                                Button("设置指定品格...") { showSetFretAlert(for: stringIndex, column: col) }
                                                Divider()
                                                Button("清除标记", role: .destructive) { 
                                                    markers[stringIndex][col] = nil
                                                    grid[stringIndex][col] = false
                                                }
                                            }

                                        if let m = markers[stringIndex][col] {
                                            Text(markerText(for: m))
                                                .font(.caption).bold().foregroundColor(.white)
                                                .padding(4).background(Color.black.opacity(0.5)).cornerRadius(4)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Footer row with UP buttons
                        HStack(spacing: spacing) {
                            Spacer().frame(width: labelWidth)
                            ForEach(0..<cols, id: \.self) { col in
                                Button(action: { toggleStrumDirection(for: col, direction: "up") }) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.title3)
                                        .foregroundColor(strumDirections[safe: col] == "up" ? .accentColor : .secondary)
                                }
                                .buttonStyle(.plain)
                                .frame(width: computedCellWidth, height: 28)
                            }
                            Spacer().frame(width: 8)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: contentWidth)
                    Spacer()
                }
                .frame(width: totalWidth)
            }
            .frame(minHeight: CGFloat(stringCount) * 44 + 80)
        }
    }
    
    private func markerText(for marker: String) -> String {
        if marker.hasPrefix("FIXED:") {
            return "S" + (marker.split(separator: ":").last.map(String.init) ?? "")
        } else if marker.hasPrefix("FRET:") {
            return marker.split(separator: ":").last.map(String.init) ?? ""
        } else { // ROOT
            return "R"
        }
    }

    // MARK: - Actions
    private func toggleStrumDirection(for col: Int, direction: String) {
        // Reset strum state whenever a direction button is clicked
        strumStart = nil

        if strumDirections.indices.contains(col) {
            if strumDirections[col] == direction {
                strumDirections[col] = nil // Toggle off
                // Clear the column visually
                for i in 0..<stringCount {
                    grid[i][col] = false
                }
            } else {
                strumDirections[col] = direction // Set new direction
                // Clear the column to prepare for new selection
                for i in 0..<stringCount {
                    grid[i][col] = false
                }
            }
        }
    }
    private func showSetFretAlert(for string: Int, column: Int) {
        let alert = NSAlert()
        alert.messageText = "设置指定品格"
        alert.informativeText = "在 弦 \(string + 1) 上输入要演奏的品格号 (0-24)。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "品格号"
        alert.accessoryView = textField

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            if let fretNumber = Int(textField.stringValue), (0...24).contains(fretNumber) {
                markers[string][column] = "FRET:\(fretNumber)"
                if !grid[string][column] {
                    grid[string][column] = true
                }
            }
        }
    }
    
    private func toggleCell(string: Int, col: Int) {
        // If a strum direction is not set for this column, we are in Arpeggio mode.
        guard let strumDir = strumDirections[safe: col], let _ = strumDir else {
            // Arpeggio mode: toggle individual cells
            grid[string][col].toggle()
            
            // Preview the single note sound
            if grid[string][col] {
                let fingering: [StringOrInt] = [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)]
                let chordNotes = MusicTheory.chordToMidiNotes(chordDefinition: fingering, tuning: MusicTheory.standardGuitarTuning)
                let midiIndex = (stringCount - 1) - string
                if let midiNote = chordNotes[safe: midiIndex], midiNote >= 0 {
                    midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 100)
                    }
                }
            }
            return
        }

        // Strum mode for this column.
        if let startInfo = strumStart, startInfo.col == col {
            // This is the second click, defining the end of the strum.
            let startString = startInfo.string
            let endString = string

            // Clear the column to draw the final strum range.
            for i in 0..<stringCount {
                grid[i][col] = false
            }

            // Fill the range between start and end strings.
            let range = min(startString, endString)...max(startString, endString)
            for i in range {
                grid[i][col] = true
            }

            // Reset strumStart, so the next click on any column starts a new definition.
            strumStart = nil
            
            // TODO: Preview the full strum sound here
            
        } else {
            // This is the first click, defining the start of the strum.
            // Clear the column and any other strum start markers.
            for i in 0..<stringCount {
                grid[i][col] = false
            }
            
            // Mark the single start cell.
            grid[string][col] = true
            
            // Store the starting point for the next click.
            strumStart = (col: col, string: string)
            
            // TODO: Preview a single note sound to indicate start selection
        }
    }

    private func previewChordC() {
        let cMajorFingering: [StringOrInt] = [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)]
        let cMajorNotes = MusicTheory.chordToMidiNotes(chordDefinition: cMajorFingering, tuning: MusicTheory.standardGuitarTuning)
        
        let stepDuration: Double = (subdivision == 8) ? 0.35 : 0.18
        let strumNoteSpacing: Double = 0.06
        let noteSustain: Double = 0.45
        let cols = grid.first?.count ?? 0

        func getMidiNoteFor(stringIndex: Int, colIndex: Int) -> Int? {
            let midiIndex = (stringCount - 1) - stringIndex
            if let marker = markers[stringIndex][colIndex], marker.hasPrefix("FRET:"), let fret = Int(marker.split(separator: ":").last ?? "") {
                return MusicTheory.standardGuitarTuning[midiIndex] + fret
            } else {
                if let note = cMajorNotes[safe: midiIndex], note >= 0 {
                    return note
                }
            }
            return nil
        }

        for col in 0..<cols {
            var scheduledNotes: [(note: Int, order: Int)] = []
            let strumDir = strumDirections[safe: col].flatMap { $0 }

            if let direction = strumDir {
                var activeStrings: [Int] = []
                for s in 0..<stringCount {
                    if grid[s][col] {
                        activeStrings.append(s + 1) // string number 1-6
                    }
                }
                
                let orderedStrings = (direction == "down") ? activeStrings.sorted() : activeStrings.sorted().reversed()
                
                var idx = 0
                for stringNum in orderedStrings {
                    let uiIndex = stringNum - 1
                    if let note = getMidiNoteFor(stringIndex: uiIndex, colIndex: col) {
                        scheduledNotes.append((note: note, order: idx))
                        idx += 1
                    }
                }
            } else {
                // Arpeggio logic
                for s in 0..<stringCount {
                    if grid[s][col] {
                        if let note = getMidiNoteFor(stringIndex: s, colIndex: col) {
                            scheduledNotes.append((note: note, order: 0))
                        }
                    }
                }
            }

            let baseTime = Double(col) * stepDuration
            for (note, order) in scheduledNotes {
                let offset = (strumDir != nil) ? Double(order) * strumNoteSpacing : 0.0
                let onTime = baseTime + offset
                let offTime = onTime + noteSustain

                DispatchQueue.main.asyncAfter(deadline: .now() + onTime) {
                    midiManager.sendNoteOn(note: UInt8(note), velocity: 110)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + offTime) {
                    midiManager.sendNoteOff(note: UInt8(note), velocity: 0)
                }
            }
        }
    }

    private func updateGridSize() {
        let timeParts = timeSignature.split(separator: "/").map(String.init)
        let numerator = Double(timeParts.first ?? "4") ?? 4.0
        let denominator = Double(timeParts.last ?? "4") ?? 4.0
        let cols = Int((numerator / denominator) * Double(subdivision))
        
        var newGrid = Array(repeating: Array(repeating: false, count: cols), count: stringCount)
        var newMarkers: [[String?]] = Array(repeating: Array(repeating: nil, count: cols), count: stringCount)
        
        let oldCols = grid.first?.count ?? 0
        let copyCols = min(cols, oldCols)
        if copyCols > 0 {
            for r in 0..<stringCount {
                for c in 0..<copyCols {
                    newGrid[r][c] = grid[r][c]
                    newMarkers[r][c] = markers[r][c]
                }
            }
        }
        
        self.grid = newGrid
        self.markers = newMarkers
        self.strumDirections = Array(repeating: nil, count: cols)
    }

    private func buildPatternFromState() -> GuitarPattern {
        var events: [PatternEvent] = []
        let cols = grid.first?.count ?? 0

        for col in 0..<cols {
            var notesForCol: [GuitarNote] = []
            var hasContent = false
            
            let strumDir = strumDirections[safe: col].flatMap { $0 }

            if let direction = strumDir {
                // Strum mode for this column
                var activeStrings: [Int] = []
                for string in 0..<stringCount {
                    if grid[string][col] {
                        activeStrings.append(string + 1)
                    }
                }

                if !activeStrings.isEmpty {
                    hasContent = true
                    // Order of notes matters for strumming.
                    if direction == "down" { // screen down, 1 -> 6, physical up-strum
                        notesForCol = activeStrings.sorted().map { .chordString($0) }
                    } else { // "up", screen up, 6 -> 1, physical down-strum
                        notesForCol = activeStrings.sorted().reversed().map { .chordString($0) }
                    }
                }
            } else {
                // Arpeggio mode
                for string in 0..<stringCount {
                    if grid[string][col] {
                        hasContent = true
                        if let m = markers[string][col] {
                            if m == "ROOT" {
                                notesForCol.append(.chordRoot("ROOT"))
                            } else if m.hasPrefix("FRET:"), let fret = Int(m.split(separator: ":").last ?? "") {
                                notesForCol.append(.specificFret(string: string + 1, fret: fret))
                            } else {
                                notesForCol.append(.chordString(string + 1))
                            }
                        } else {
                            notesForCol.append(.chordString(string + 1))
                        }
                    }
                }
            }

            if hasContent {
                let delayString = "\(col)/\(subdivision)"
                let deltaValue: Double? = (strumDir != nil) ? 15 : nil
                events.append(PatternEvent(delay: delayString, notes: notesForCol, delta: deltaValue))
            }
        }
        return GuitarPattern(id: id, name: name, pattern: events)
    }

    private func updateSmartName() {
        let newName = buildPatternFromState().generateSmartName(timeSignature: self.timeSignature)

        // If the name hasn't changed, do nothing to avoid unnecessary view updates.
        if newName == self.name { return }

        let isDefaultName = self.name.isEmpty || self.name == "新演奏模式" || self.name == "新模式"
        
        // Check if the current name appears to be auto-generated.
        // An auto-generated name consists of digits, '.', '_', 'R', 'P', '上', '下'.
        let isPreviouslyAutoGenerated = self.name.range(of: "^[0-9._RP上下]+$", options: .regularExpression) != nil
        
        if isDefaultName || isPreviouslyAutoGenerated {
            self.name = newName
        }
    }

    private func save() {
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalName.isEmpty {
            // Optionally, show an alert for empty name
            return
        }

        // 1. Gather existing names for the current time signature
        var namesInCurrentTimeSignature = Set<String>()
        
        // Add built-in names for the current time signature
        if let systemPatterns = appData.patternLibrary?[timeSignature] {
            for pattern in systemPatterns {
                namesInCurrentTimeSignature.insert(pattern.name.lowercased())
            }
        }
        
        // Add custom names for the current time signature
        if let customPatterns = customPlayingPatternManager.customPlayingPatterns[timeSignature] {
            for pattern in customPatterns {
                namesInCurrentTimeSignature.insert(pattern.name.lowercased())
            }
        }

        // 2. Check for conflict
        var isConflict = false
        let lowercasedFinalName = finalName.lowercased()

        if isEditing {
            let originalName = editingPatternData?.pattern.name
            // If name has changed, check if the new name conflicts with an existing name in the same time signature.
            if lowercasedFinalName != originalName?.lowercased() {
                if namesInCurrentTimeSignature.contains(lowercasedFinalName) {
                    isConflict = true
                }
            }
        } else { // Creating a new pattern
            if namesInCurrentTimeSignature.contains(lowercasedFinalName) {
                isConflict = true
            }
        }

        // 3. Handle result
        if isConflict {
            showNameConflictAlert = true
        } else {
            // Update the name before building the pattern, in case it was just trimmed
            self.name = finalName
            let newPattern = buildPatternFromState()
            customPlayingPatternManager.addOrUpdatePattern(pattern: newPattern, timeSignature: timeSignature)
            dismiss()
        }
    }
}

// Safe array subscript helper
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
