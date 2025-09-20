
import SwiftUI

// MARK: - Main Editor View

struct MelodicLyricEditorView: View {
    @Binding var segment: MelodicLyricSegment

    // Editor State
    @State private var selectedItems: Set<UUID> = []
    @State private var currentTechnique: PlayingTechnique = .normal
    @State private var gridSizeInSteps: Int = 4 // 16th notes
    @State private var zoomLevel: CGFloat = 1.0
    @State private var isSyncingTechnique = false

    // Popover State
    @State private var newItemPopoverState: NewItemPopoverState? = nil
    @State private var editingItemState: EditItemPopoverState? = nil

    // In-place name editing state
    @State private var isEditingName = false
    @FocusState private var isNameFieldFocused: Bool

    // Layout constants
    private let beatWidth: CGFloat = 120
    private var stepWidth: CGFloat { (beatWidth / 4) * zoomLevel }
    private let trackHeight: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. In-place Editable Title
            HStack {
                Spacer()
                if isEditingName {
                    TextField("Segment Name", text: $segment.name)
                        .font(.largeTitle).textFieldStyle(.plain).multilineTextAlignment(.center)
                        .focused($isNameFieldFocused)
                        .onSubmit { isEditingName = false }.onDisappear { isEditingName = false }
                } else {
                    Text(segment.name).font(.largeTitle).fontWeight(.bold)
                        .onTapGesture(count: 2) { isEditingName = true; isNameFieldFocused = true }
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal)
            .padding(.bottom, 4)

            // 2. Toolbar
            MelodicLyricToolbar(
                currentTechnique: $currentTechnique,
                gridSizeInSteps: $gridSizeInSteps,
                zoomLevel: $zoomLevel,
                segmentLengthInBars: $segment.lengthInBars
            ).padding().background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            // 3. Main Content Editor
            ScrollView([.horizontal]) {
                ZStack(alignment: .topLeading) {
                    // Layer 1: Background Grid
                    MelodicLyricGridBackground(
                        lengthInBars: segment.lengthInBars, beatsPerBar: 4, beatWidth: beatWidth,
                        trackHeight: trackHeight, zoomLevel: zoomLevel, stepsPerBeat: 4,
                        gridSizeInSteps: gridSizeInSteps
                    )

                    ForEach(segment.items) { item in
                        MelodicLyricCellView(item: item, isSelected: selectedItems.contains(item.id), stepWidth: stepWidth)
                            .offset(x: CGFloat(item.position) * stepWidth)
                            .onTapGesture { selectItem(item.id) }
                            .onTapGesture(count: 2) { self.editingItemState = .init(item: item) }
                    }
                }
                .frame(width: CGFloat(segment.lengthInBars * 4) * beatWidth * zoomLevel, height: trackHeight)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { location in handleBackgroundTap(at: location) }
            }
            .background(Color(NSColor.textBackgroundColor))
            .popover(item: $newItemPopoverState) { state in
                NewItemPopover(popoverState: state, onCreate: createNewItem)
            }
            .popover(item: $editingItemState) { state in
                EditItemPopover(popoverState: state, onUpdate: updateItem)
            }
            
            Divider()
            
            // 4. Status Bar
            HStack(spacing: 0) {
                Text("Selected: \(selectedItems.count) items").padding(.horizontal)
                Spacer()
                Text("Length: \(segment.lengthInBars) bars").padding(.horizontal)
                Spacer()
                Text("Items: \(segment.items.count)").padding(.horizontal)
            }
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onKeyDown(perform: handleKeyDown)
        .onChange(of: selectedItems, perform: syncTechniqueWithSelection)
        .onChange(of: currentTechnique, perform: applyTechniqueToSelectedItems)
    }
    
    // MARK: - Private Methods

    private func handleBackgroundTap(at location: CGPoint) {
        selectedItems.removeAll()
        let totalSteps = segment.lengthInBars * 4 * 4
        let tappedStep = Int(location.x / stepWidth)
        
        guard tappedStep >= 0 && tappedStep < totalSteps else { return }
        
        let snappedStep = (tappedStep / gridSizeInSteps) * gridSizeInSteps
        self.newItemPopoverState = NewItemPopoverState(id: UUID(), position: snappedStep)
    }
    
    private func createNewItem(word: String, pitch: Int, octave: Int, position: Int) {
        let techniqueValue: PlayingTechnique? = currentTechnique == .normal ? nil : currentTechnique
        let newItem = MelodicLyricItem(word: word, position: position, pitch: pitch, octave: octave, technique: techniqueValue)
        segment.items.append(newItem)
        segment.items.sort { $0.position < $1.position }
        newItemPopoverState = nil
    }

    private func updateItem(id: UUID, newWord: String, newPitch: Int, newOctave: Int, newTechnique: PlayingTechnique) {
        guard let index = segment.items.firstIndex(where: { $0.id == id }) else { return }
        segment.items[index].word = newWord
        segment.items[index].pitch = newPitch
        segment.items[index].octave = newOctave
        segment.items[index].technique = newTechnique == .normal ? nil : newTechnique
        editingItemState = nil
    }
    
    private func selectItem(_ itemID: UUID, addToSelection: Bool = false) {
        if addToSelection {
            if selectedItems.contains(itemID) { selectedItems.remove(itemID) } else { selectedItems.insert(itemID) }
        } else {
            selectedItems = [itemID]
        }
    }
    
    private func deleteSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        segment.items.removeAll { selectedItems.contains($0.id) }
        selectedItems.removeAll()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 51 { // Backspace/Delete
            deleteSelectedItems()
            return true
        }
        return false
    }

    private func syncTechniqueWithSelection(_ selection: Set<UUID>) {
        guard !selection.isEmpty else { return }
        let techniques = segment.items.filter { selection.contains($0.id) }
            .map { $0.technique ?? .normal }

        guard let firstTechnique = techniques.first else {
            if currentTechnique != .normal { currentTechnique = .normal }
            return
        }

        let shouldResetToNormal = techniques.contains { $0 != firstTechnique }

        let newTechnique: PlayingTechnique = shouldResetToNormal ? .normal : firstTechnique
        if currentTechnique != newTechnique {
            isSyncingTechnique = true
            currentTechnique = newTechnique
        }
    }

    private func applyTechniqueToSelectedItems(_ technique: PlayingTechnique) {
        if isSyncingTechnique {
            isSyncingTechnique = false
            return
        }
        guard !selectedItems.isEmpty else { return }
        for index in segment.items.indices {
            guard selectedItems.contains(segment.items[index].id) else { continue }
            segment.items[index].technique = technique == .normal ? nil : technique
        }
    }
}

// MARK: - Popover State & Views

struct NewItemPopoverState: Identifiable {
    var id: UUID
    var position: Int
}

struct EditItemPopoverState: Identifiable {
    var id: UUID { item.id }
    var item: MelodicLyricItem
}

struct NewItemPopover: View {
    let popoverState: NewItemPopoverState
    let onCreate: (String, Int, Int, Int) -> Void
    
    @State private var word: String = ""
    @State private var pitch: Int = 5
    @State private var octave: Int = 0
    @FocusState private var isWordFieldFocused: Bool

    var body: some View {
        VStack(spacing: 15) {
            Text("New Lyric at step \(popoverState.position)").font(.headline)
            TextField("Lyric Word", text: $word).textFieldStyle(.roundedBorder).focused($isWordFieldFocused).onAppear { isWordFieldFocused = true }
            HStack {
                Stepper("Pitch: \(pitch)", value: $pitch, in: 1...7)
                Stepper("Octave: \(octave)", value: $octave, in: -2...2)
            }
            Button("Create") { if !word.isEmpty { onCreate(word, pitch, octave, popoverState.position) } }.keyboardShortcut(.defaultAction)
        }.padding().frame(minWidth: 250)
    }
}

struct EditItemPopover: View {
    let popoverState: EditItemPopoverState
    let onUpdate: (UUID, String, Int, Int, PlayingTechnique) -> Void

    @State private var word: String
    @State private var pitch: Int
    @State private var octave: Int
    @State private var technique: PlayingTechnique
    @FocusState private var isWordFieldFocused: Bool

    init(popoverState: EditItemPopoverState, onUpdate: @escaping (UUID, String, Int, Int, PlayingTechnique) -> Void) {
        self.popoverState = popoverState
        self.onUpdate = onUpdate
        _word = State(initialValue: popoverState.item.word)
        _pitch = State(initialValue: popoverState.item.pitch)
        _octave = State(initialValue: popoverState.item.octave)
        _technique = State(initialValue: popoverState.item.technique ?? .normal)
    }

    var body: some View {
        VStack(spacing: 15) {
            Text("Edit Lyric").font(.headline)
            TextField("Lyric Word", text: $word).textFieldStyle(.roundedBorder).focused($isWordFieldFocused).onAppear { isWordFieldFocused = true }
            HStack {
                Stepper("Pitch: \(pitch)", value: $pitch, in: 1...7)
                Stepper("Octave: \(octave)", value: $octave, in: -2...2)
            }
            Picker("Technique", selection: $technique) {
                ForEach(PlayingTechnique.allCases) { Text($0.chineseName).tag($0) }
            }
            Button("Update") {
                guard !word.isEmpty else { return }
                onUpdate(popoverState.item.id, word, pitch, octave, technique)
            }.keyboardShortcut(.defaultAction)
        }.padding().frame(minWidth: 250)
    }
}

// MARK: - Subviews

struct MelodicLyricToolbar: View {
    @Binding var currentTechnique: PlayingTechnique
    @Binding var gridSizeInSteps: Int
    @Binding var zoomLevel: CGFloat
    @Binding var segmentLengthInBars: Int
    @State private var showingSettings = false
    // Corrected grid options: Label -> Number of 16th-note steps
    private let gridOptions: [(String, Int)] = [("1/4", 4), ("1/8", 2), ("1/16", 1)]

    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            Picker("Technique", selection: $currentTechnique) {
                ForEach(PlayingTechnique.allCases) { Text($0.chineseName).tag($0) }
            }.frame(minWidth: 80).help("Playing Technique")
            Spacer()
            Picker("Grid", selection: $gridSizeInSteps) {
                ForEach(gridOptions, id: \.1) { Text($0.0).tag($0.1) }
            }.frame(minWidth: 80).help("Grid Snap")
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Slider(value: $zoomLevel, in: 0.5...4.0).frame(width: 100)
            }.help("Zoom Level")
            Spacer()
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
            }.buttonStyle(.bordered).popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                LyricSegmentSettingsView(lengthInBars: $segmentLengthInBars)
            }
        }.pickerStyle(.menu)
    }
}

struct LyricSegmentSettingsView: View {
    @Binding var lengthInBars: Int
    var body: some View {
        VStack(spacing: 12) {
            Text("Segment Properties").font(.headline)
            HStack {
                Text("Length (bars):")
                TextField("Length", value: $lengthInBars, format: .number).frame(width: 60)
            }
        }.padding()
    }
}

struct MelodicLyricGridBackground: View {
    let lengthInBars: Int, beatsPerBar: Int, beatWidth: CGFloat, trackHeight: CGFloat, zoomLevel: CGFloat, stepsPerBeat: Int, gridSizeInSteps: Int
    private var stepWidth: CGFloat { (beatWidth / CGFloat(stepsPerBeat)) * zoomLevel }

    var body: some View {
        Canvas { context, size in
            let totalSteps = lengthInBars * beatsPerBar * stepsPerBeat
            for step in stride(from: 0, through: totalSteps, by: gridSizeInSteps) {
                let x = CGFloat(step) * stepWidth
                let isBeatLine = step % stepsPerBeat == 0
                let isBarLine = isBeatLine && (step / stepsPerBeat) % beatsPerBar == 0
                let lineColor: Color = isBarLine ? .primary.opacity(0.8) : (isBeatLine ? .primary.opacity(0.5) : .primary.opacity(0.2))
                let lineWidth: CGFloat = isBarLine ? 1.0 : 0.5
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: trackHeight)) }, with: .color(lineColor), lineWidth: lineWidth)
            }
        }
    }
}

struct MelodicLyricCellView: View {
    let item: MelodicLyricItem
    let isSelected: Bool
    let stepWidth: CGFloat

    // Dynamically calculate font sizes based on the cell's width
    private var pitchFontSize: CGFloat {
        return max(8, min(24, stepWidth * 0.6))
    }

    private var wordFontSize: CGFloat {
        return max(6, min(16, stepWidth * 0.4))
    }

    private var techniqueFontSize: CGFloat {
        return max(5, min(12, stepWidth * 0.3))
    }

    var body: some View {
        VStack(spacing: 2) {
            // Octave dots (top)
            OctaveView(octave: item.octave)
                .foregroundColor(isSelected ? .white : .primary)

            // Pitch number and technique
            HStack(spacing: 1) {
                Text("\(item.pitch)")
                    .font(.system(size: pitchFontSize, weight: .bold, design: .monospaced))
                
                if let technique = item.technique {
                    Text(technique.symbol)
                        .font(.system(size: techniqueFontSize))
                }
            }
            .foregroundColor(isSelected ? .white : .primary)

            // Lyric word
            Text(item.word)
                .font(.system(size: wordFontSize, weight: .regular))
                .foregroundColor(isSelected ? .white : .primary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .shadow(radius: 1, y: 1)
        .frame(width: stepWidth - 2) // Leave a small gap between cells
    }
}

struct OctaveView: View {
    let octave: Int
    var body: some View {
        HStack(spacing: 2) {
            if octave > 0 { ForEach(0..<octave, id: \.self) { _ in Circle().fill().frame(width: 4, height: 4) } }
        }.frame(height: 8)
    }
}

// MARK: - Preview Provider

struct MelodicLyricEditorView_Previews: PreviewProvider {
    @State static var mockSegment: MelodicLyricSegment = {
        var segment = MelodicLyricSegment(name: "Test Verse", lengthInBars: 2)
        segment.items = [
            MelodicLyricItem(word: "你", position: 0, pitch: 5, octave: 0),
            MelodicLyricItem(word: "好", position: 2, pitch: 6, octave: 0),
            MelodicLyricItem(word: "世", position: 4, pitch: 1, octave: 1, technique: .vibrato),
            MelodicLyricItem(word: "界", position: 6, pitch: 7, octave: 0)
        ]
        return segment
    }()

    static var previews: some View {
        MelodicLyricEditorView(segment: $mockSegment).frame(width: 800, height: 400)
    }
}
