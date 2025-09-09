
import SwiftUI

struct PlayingPatternEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager

    // Form state
    @State private var id: String = ""
    @State private var name: String = "新演奏模式"
    @State private var timeSignature: String = "4/4" // 4/4,3/4,6/8
    @State private var subdivision: Int = 8 // 8 or 16

    // Fixed 6 strings, grid: rows = 6 strings, cols = computed
    private let stringCount = 6
    @State private var grid: [[Bool]] = Array(repeating: Array(repeating: false, count: 8), count: 6)
    // Optional markers for ROOT or FIXED string (nil / "ROOT" / "FIXED:1")
    @State private var markers: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 6)

    // Strum mode vs Arpeggio (分解)
    @State private var modeIsStrum: Bool = false
    // For strum mode, store direction per column: nil/"up"/"down"
    @State private var strumDirections: [String?] = Array(repeating: nil, count: 8)

    let editingPatternData: PlayingPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    init(editingPatternData: PlayingPatternEditorData? = nil) {
        self.editingPatternData = editingPatternData
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
                            Picker("拍子", selection: $timeSignature) {
                                Text("4/4").tag("4/4")
                                Text("3/4").tag("3/4")
                                Text("6/8").tag("6/8")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)

                            Picker("细分", selection: $subdivision) {
                                Text("8分音符").tag(8)
                                Text("16分音符").tag(16)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }
                    .padding(.horizontal)

                    // --- Mode toggle ---
                    HStack {
                        Toggle(isOn: $modeIsStrum) {
                            Text(modeIsStrum ? "扫弦模式" : "分解和弦模式")
                        }
                        .toggleStyle(.button)
                        Spacer()
                        Button("预览整和弦 (C)") { previewChordC() }
                    }
                    .padding(.horizontal)

                    Divider()

                    // --- Grid editor (header + grid scroll together for alignment) ---
                    VStack(spacing: 8) {
                        combinedGridArea()
                        Text("提示：点击格子预览单音；右键(或长按)设置 ROOT 或 固定弦")
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
        .onAppear(perform: setupInitialState)
        .onChange(of: timeSignature) { _ in updateGridSize() }
        .onChange(of: subdivision) { _ in updateGridSize() }
    }

    // MARK: - Views
    private func timelineHeaderView() -> some View {
        let cols = grid.first?.count ?? 8
    let labelWidth: CGFloat = 44
        let spacing: CGFloat = 6
        let cellWidth: CGFloat = subdivision == 8 ? 44 : 36

        return ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: spacing) {
                // leading label spacer to align with string labels in grid
                Spacer().frame(width: labelWidth)
                ForEach(0..<cols, id: \.self) { col in
                    VStack(spacing: 4) {
                            if modeIsStrum {
                                // compact menu button to choose None/Down/Up to avoid overlapping segmented control
                                let current = strumDirections.indices.contains(col) ? (strumDirections[col] ?? "none") : "none"
                                Menu {
                                    Button("—") { strumDirections[col] = nil }
                                    Button("↓") { strumDirections[col] = "down" }
                                    Button("↑") { strumDirections[col] = "up" }
                                } label: {
                                    Text(current == "down" ? "↓" : current == "up" ? "↑" : "—")
                                        .font(.caption)
                                        .frame(width: cellWidth, height: 28)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                                }
                            } else {
                            Text("\(col)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: cellWidth)
                        }
                    }
                }
                Spacer().frame(width: 8)
            }
            .padding(.vertical, 6)
            .padding(.leading, 8)
        }
    }

    private func gridView() -> some View {
        let cols = grid.first?.count ?? 8
    let labelWidth: CGFloat = 44
        let spacing: CGFloat = 6
        let cellWidth: CGFloat = subdivision == 8 ? 44 : 36
        return ScrollView([.horizontal, .vertical]) {
            VStack(spacing: spacing) {
                ForEach(0..<stringCount, id: \.self) { stringIndex in
                    HStack(spacing: spacing) {
                        // String label
                        Text("弦 \(stringIndex + 1)")
                            .frame(width: labelWidth, alignment: .trailing)
                            .font(.subheadline)

                        ForEach(0..<cols, id: \.self) { col in
                            ZStack {
                                Rectangle()
                                    .fill(grid[stringIndex][col] ? Color.accentColor.opacity(0.9) : Color.gray.opacity(0.12))
                                    .frame(width: cellWidth, height: 36)
                                    .cornerRadius(6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleCell(string: stringIndex, col: col)
                                    }
                                    .contextMenu(menuItems: {
                                        Button("设置为 ROOT") { markers[stringIndex][col] = "ROOT" }
                                        Button("设置为 固定弦") { markers[stringIndex][col] = "FIXED:\(stringIndex+1)" }
                                        Button("清除标记") { markers[stringIndex][col] = nil }
                                    })

                                if let m = markers[stringIndex][col] {
                                    Text(m.hasPrefix("FIXED") ? String(m.split(separator: ":")[1]) : "ROOT")
                                        .font(.caption2).bold().foregroundColor(.white)
                                        .padding(4).background(Color.black.opacity(0.5)).cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
        }
    }

    // Combined header + grid in a single horizontal scroll view to ensure perfect column alignment
    private func combinedGridArea() -> some View {
        let cols = grid.first?.count ?? 8
    let labelWidth: CGFloat = 44
        let spacing: CGFloat = 6
        let cellWidth: CGFloat = subdivision == 8 ? 44 : 36

        // Use vertical-only scroll with GeometryReader to compute cellWidth so it fits horizontally
    return ScrollView(.vertical) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                // account for paddings and trailing spacer
                let endPadding: CGFloat = 16
                let totalSpacing = CGFloat(max(0, cols - 1)) * spacing + endPadding
                let availableForCells = max(40, totalWidth - labelWidth - totalSpacing - 16) // 16 side padding
                // For 8th notes prefer up to 44, for 16th allow smaller but not less than 20
                let rawCell = availableForCells / CGFloat(max(1, cols))
                let minCell: CGFloat = subdivision == 8 ? 28 : 20
                let maxCell: CGFloat = subdivision == 8 ? 44 : 36
                let computedCellWidth = min(maxCell, max(minCell, floor(rawCell)))

                // compute content width and center it
                let contentWidth = labelWidth + CGFloat(cols) * computedCellWidth + CGFloat(max(0, cols - 1)) * spacing + 16

                // Center the inner content by using flexible spacers and an exact content width.
                HStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 6) {
                        // Header row
                        HStack(spacing: spacing) {
                            Spacer().frame(width: labelWidth)
                            ForEach(0..<cols, id: \.self) { col in
                                if modeIsStrum {
                                    let current = strumDirections.indices.contains(col) ? (strumDirections[col] ?? "none") : "none"
                                    Menu {
                                        Button("—") { strumDirections[col] = nil }
                                        Button("↓") { strumDirections[col] = "down" }
                                        Button("↑") { strumDirections[col] = "up" }
                                    } label: {
                                        Text(current == "down" ? "↓" : current == "up" ? "↑" : "—")
                                            .font(.caption)
                                            .frame(width: computedCellWidth, height: 28)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                                    }
                                } else {
                                    Text("\(col)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .frame(width: computedCellWidth)
                                }
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
                                            .contextMenu(menuItems: {
                                                Button("设置为 ROOT") { markers[stringIndex][col] = "ROOT" }
                                                Button("设置为 固定弦") { markers[stringIndex][col] = "FIXED:\(stringIndex+1)" }
                                                Button("清除标记") { markers[stringIndex][col] = nil }
                                            })

                                        if let m = markers[stringIndex][col] {
                                            Text(m.hasPrefix("FIXED") ? String(m.split(separator: ":")[1]) : "ROOT")
                                                .font(.caption2).bold().foregroundColor(.white)
                                                .padding(4).background(Color.black.opacity(0.5)).cornerRadius(4)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(width: contentWidth)
                    Spacer()
                }
                .frame(width: totalWidth)
            }
            .frame(minHeight: CGFloat(stringCount) * 44 + 40) // ensure geometry has height
    }
    }

    // MARK: - Actions
    private func toggleCell(string: Int, col: Int) {
        // toggle and play single note preview
        grid[string][col].toggle()
            if grid[string][col] {
                // Play the note for preview using the C chord mapping so single-note preview
                // matches the chord preview pitch for that string.
                let fingering: [StringOrInt] = [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)]
                let chordNotes = MusicTheory.chordToMidiNotes(chordDefinition: fingering, tuning: MusicTheory.standardGuitarTuning)

                // UI string index 0 == 弦1 (high E). chordNotes is indexed low->high, so map UI index -> midi index
                let midiIndex = (stringCount - 1) - string
                if let midiNote = chordNotes[safe: midiIndex], midiNote >= 0 {
                    midiManager.sendNoteOn(note: UInt8(midiNote), velocity: 100)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        midiManager.sendNoteOff(note: UInt8(midiNote), velocity: 100)
                    }
                }
        }
    }

    private func previewChordC() {
        // C major fingering (E A D G B E) -> [x,3,2,0,1,0]
        // Use StringOrInt to match MusicTheory expectations
        let fingering: [StringOrInt] = [.string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)]
        let chordNotes = MusicTheory.chordToMidiNotes(chordDefinition: fingering, tuning: MusicTheory.standardGuitarTuning)

        // Determine step timing (simple heuristic: longer for 8th, shorter for 16th)
        let stepDuration: Double = (subdivision == 8) ? 0.35 : 0.18
        let strumNoteSpacing: Double = 0.06
        let noteSustain: Double = 0.45

        let cols = grid.first?.count ?? 0

        for col in 0..<cols {
            // collect notes for this column according to mode and markers
            var scheduledNotes: [(note: Int, order: Int)] = []

            if modeIsStrum {
                if let dir = (strumDirections.indices.contains(col) ? strumDirections[col] : nil) {
                    // explicit direction -> use fixed string order (down: 6..1, up: 1..6)
                    let fixedOrder: [Int] = (dir == "down") ? [6,5,4,3,2,1] : [1,2,3,4,5,6]
                    var idx = 0
                    // include all strings in fixed order regardless of which cells the user clicked
                    for n in fixedOrder {
                        let uiIndex = n - 1
                        let midiIndex = (stringCount - 1) - uiIndex
                        if let note = chordNotes[safe: midiIndex], note >= 0 {
                            scheduledNotes.append((note: note, order: idx))
                            idx += 1
                        }
                    }
                } else {
                    // no direction -> play simultaneously (like arpeggio/simultaneous)
                    for s in 0..<stringCount {
                        if grid[s][col] {
                            let midiIndex = (stringCount - 1) - s
                            if let note = chordNotes[safe: midiIndex], note >= 0 {
                                scheduledNotes.append((note: note, order: 0))
                            }
                        }
                    }
                }
            } else {
                // arpeggio / simultaneous: play all selected strings at same time
                for s in 0..<stringCount {
                    if grid[s][col] {
                        let midiIndex = (stringCount - 1) - s
                        if let note = chordNotes[safe: midiIndex], note >= 0 {
                            scheduledNotes.append((note: note, order: 0))
                        }
                    }
                }
            }

            // schedule the notes for this column
                let baseTime = Double(col) * stepDuration
            for (note, order) in scheduledNotes {
                let offset = modeIsStrum ? Double(order) * strumNoteSpacing : 0.0
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

    private func setupInitialState() {
        // initialize based on editing data if provided
        updateGridSize()
        if let data = editingPatternData {
            self.id = data.id
            self.name = data.pattern.name
            self.timeSignature = data.timeSignature

            // Inspect the first event to determine the subdivision
            if let firstEvent = data.pattern.pattern.first {
                let delay = firstEvent.delay
                let components = delay.split(separator: "/")
                if components.count == 2, let denominator = Int(components[1]) {
                    if denominator == 16 {
                        self.subdivision = 16
                    } else {
                        self.subdivision = 8 // Default to 8 for safety
                    }
                }
            }
            
            // After potentially changing subdivision, we must resize the grid
            updateGridSize()

            // If any event has a non-zero delta, treat the whole pattern as strum mode
            if data.pattern.pattern.contains(where: { ($0.delta ?? 0) != 0 }) {
                self.modeIsStrum = true
            }
            // Parse existing pattern into grid/markers/strumDirections
            let cols = grid.first?.count ?? 0
            // Clear
            for r in 0..<stringCount {
                for c in 0..<cols { grid[r][c] = false; markers[r][c] = nil }
            }

            for event in data.pattern.pattern {
                // parse delay into a column index
                if let delayFraction = MusicTheory.parsePatternDelay(event.delay) {
                    let col = Int(round(delayFraction * Double(subdivision)))
                    let safeCol = max(0, min((grid.first?.count ?? 1) - 1, col))

                    // determine if this is a strum event
                    let isStrum = (event.delta ?? 0) > 0 && event.notes.count > 1
                    if isStrum {
                        // map notes to ints when possible
                        let intNotes = event.notes.compactMap { note -> Int? in
                            switch note {
                            case .int(let v): return v
                            case .string(let s):
                                // Attempt to parse ROOT-<n>
                                if s == "ROOT" { return nil }
                                if s.hasPrefix("ROOT-"), let last = Int(s.split(separator: "-").last ?? "") { return last }
                                return nil
                            }
                        }
                        if !intNotes.isEmpty {
                            // set grid for those strings; intNotes are 1..6
                            for n in intNotes {
                                if (1...6).contains(n) {
                                    grid[n-1][safeCol] = true
                                }
                            }
                            // detect direction
                            if let first = intNotes.first, let last = intNotes.last {
                                strumDirections[safeCol] = (first > last) ? "down" : "up"
                            }
                        }
                    } else {
                        // single or multiple notes treated as individual hits
                        for note in event.notes {
                            switch note {
                            case .int(let v):
                                if (1...6).contains(v) { grid[v-1][safeCol] = true }
                            case .string(let s):
                                if s == "ROOT" {
                                    // place a ROOT marker on a reasonable default string (string 5 -> index 4) if available
                                    let idx = min(4, stringCount-1)
                                    markers[idx][safeCol] = "ROOT"
                                    grid[idx][safeCol] = true
                                } else if s.hasPrefix("ROOT-"), let last = Int(s.split(separator: "-").last ?? "" ) {
                                    // ROOT-n -> place marker on string index (5 - n)
                                    let stringNum = 5 - last
                                    if (1...6).contains(stringNum) {
                                        let idx = stringNum - 1
                                        markers[idx][safeCol] = "ROOT"
                                        grid[idx][safeCol] = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // default id as UUID string (not shown to user)
            self.id = UUID().uuidString
        }
    }

    private func updateGridSize() {
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let cols = beats * (subdivision == 8 ? 2 : 4)
        // resize grid while preserving existing data where possible
        for r in 0..<stringCount {
            if grid[r].count != cols {
                let old = grid[r]
                grid[r] = Array(repeating: false, count: cols)
                for i in 0..<min(old.count, cols) { grid[r][i] = old[i] }
            }
        }
        // markers
        for r in 0..<stringCount {
            if markers[r].count != cols {
                let old = markers[r]
                markers[r] = Array(repeating: nil, count: cols)
                for i in 0..<min(old.count, cols) { markers[r][i] = old[i] }
            }
        }
        if strumDirections.count != cols {
            let old = strumDirections
            strumDirections = Array(repeating: nil, count: cols)
            for i in 0..<min(old.count, cols) { strumDirections[i] = old[i] }
        }
    }

    private func save() {
        // Convert grid into PatternEvent array compatible with existing PatternEvent (delay, notes)
        var events: [PatternEvent] = []
        let cols = grid.first?.count ?? 0

        for col in 0..<cols {
            // collect notes for this column
            var notesForCol: [NoteValue] = []
            // If mode is strum, we will collect strings and order by direction
            if modeIsStrum {
                // If direction is nil, per spec we treat this as "no entry" and skip this column
                guard let dir = (strumDirections.indices.contains(col) ? strumDirections[col] : nil) else {
                    continue
                }
                // fixed strum order when a direction is set
                let fixedOrder: [Int] = (dir == "up") ? [6,5,4,3,2,1] : [1,2,3,4,5,6]
                // include all strings in fixed order regardless of clicked cells
                for n in fixedOrder { notesForCol.append(.int(n)) }
            } else {
                for string in 0..<stringCount {
                    if grid[string][col] {
                        if let m = markers[string][col], m.hasPrefix("ROOT") {
                            // If marker says ROOT or ROOT-N, try to preserve
                            if m == "ROOT" {
                                notesForCol.append(.string("ROOT"))
                            } else if m.hasPrefix("FIXED") {
                                // FIXED:NUM -> store as that string number
                                if let num = Int(m.split(separator: ":")[1]) { notesForCol.append(.int(num)) }
                                else { notesForCol.append(.int(string+1)) }
                            } else {
                                notesForCol.append(.string("ROOT"))
                            }
                        } else {
                            // store as fixed string number 1..6
                            notesForCol.append(.int(string+1))
                        }
                    }
                }
            }

            if !notesForCol.isEmpty {
                let delayString = "\(col)/\(subdivision)"
                var deltaValue: Double? = nil
                if modeIsStrum {
                    if let dir = (strumDirections.indices.contains(col) ? strumDirections[col] : nil) {
                        // only treat as a strum (delta) when a direction is explicitly set
                        deltaValue = 15
                    } else {
                        deltaValue = nil
                    }
                }
                events.append(PatternEvent(delay: delayString, notes: notesForCol, delta: deltaValue))
            }
        }

        let newPattern = GuitarPattern(id: id, name: name, pattern: events)
        customPlayingPatternManager.addOrUpdatePattern(pattern: newPattern, timeSignature: timeSignature)
        dismiss()
    }
}

// Safe array subscript helper
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
