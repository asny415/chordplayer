import SwiftUI

fileprivate struct ChordEditorData: Identifiable {
    let id: String
    let fingering: [StringOrInt]
}

/// A visually enhanced view for managing custom chords.
struct CustomChordLibraryView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var customChordManager = CustomChordManager.shared
    
    @State private var searchText: String = ""
    @State private var showingCreateSheet = false
    @State private var chordToEdit: ChordEditorData? = nil
    
    // For hover effects
    @State private var hoveredChord: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBar.padding([.horizontal, .bottom])
            Divider()
            chordGrid
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 700)
        .background(Color.black.opacity(0.2))
        .sheet(item: $chordToEdit) { data in
            CustomChordEditorView(chordName: data.id, initialFingering: data.fingering)
                .environmentObject(appData)
                .environmentObject(chordPlayer)
                .environmentObject(midiManager)
        }
        .sheet(isPresented: $showingCreateSheet) {
            CustomChordCreatorView()
                .environmentObject(appData)
                .environmentObject(chordPlayer)
                .environmentObject(midiManager)
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义和弦库")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("管理您的专属和弦收藏")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(20)
    }
    
    private var searchBar: some View {
        HStack {
            TextField("􀊫 搜索和弦...", text: $searchText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            
            Button(action: { showingCreateSheet = true }) {
                Label("创建新和弦", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
        }
    }
    
    private var chordGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                ForEach(customChordManager.customChordNames.filter { searchText.isEmpty ? true : $0.localizedCaseInsensitiveContains(searchText) }, id: \.self) { chordName in
                    chordCard(chordName: chordName)
                }
            }
            .padding(20)
            .animation(.default, value: customChordManager.customChordNames)
        }
    }
    
    private func chordCard(chordName: String) -> some View {
        let fingering = customChordManager.customChords[chordName] ?? []
        let isHovered = hoveredChord == chordName
        
        return VStack(spacing: 12) {
            Text(chordName.replacingOccurrences(of: "_", with: " "))
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)

            ChordDiagramView(frets: fingering, color: .primary)
                .frame(height: 80)
            
            HStack(spacing: 20) {
                Button(action: { playChord(chordName) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("试听")
                
                Button(action: { editChord(chordName) }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: { deleteChord(chordName) }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("删除")
            }
        }
        .padding(15)
        .background(Color(NSColor.windowBackgroundColor).opacity(isHovered ? 0.9 : 1.0))
        .cornerRadius(16)
        .shadow(radius: isHovered ? 5 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring()) {
                hoveredChord = hovering ? chordName : nil
                if !hovering {
                    chordPlayer.panic()
                }
            }
        }
    }
    
    private func playChord(_ chordName: String) {
        // If a default pattern is available, use it for a more musical preview
        if let pattern = appData.patternLibrary?[appData.performanceConfig.timeSignature]?.first {
            chordPlayer.playChord(chordName: chordName, pattern: pattern, tempo: 120, key: appData.performanceConfig.key, capo: 0, velocity: 100, duration: 1.5)
        } else if let chordDefinition = customChordManager.customChords[chordName] {
            // Otherwise, play the block chord directly
            chordPlayer.playChordDirectly(chordDefinition: chordDefinition, key: appData.performanceConfig.key, capo: 0, velocity: 100, duration: 1.5)
        }
    }
    
    private func editChord(_ chordName: String) {
        let fingering = customChordManager.customChords[chordName] ?? []
        self.chordToEdit = ChordEditorData(id: chordName, fingering: fingering)
    }
    
    private func deleteChord(_ chordName: String) {
        withAnimation {
            customChordManager.deleteChord(name: chordName)
        }
    }
}

// MARK: - Chord Editor View (Restored)
struct CustomChordEditorView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var customChordManager = CustomChordManager.shared
    
    let chordName: String
    
    @State private var frets: [Int]
    @State private var fretPosition: Int
    @State private var fingeringForSave: [StringOrInt]

    init(chordName: String, initialFingering: [StringOrInt]) {
        self.chordName = chordName
        
        let initialFrets = initialFingering.map { item -> Int in
            switch item {
            case .int(let fret): return fret
            default: return -1
            }
        }
        
        var correctedFrets = initialFrets
        while correctedFrets.count < 6 { correctedFrets.append(-1) }
        if correctedFrets.count > 6 { correctedFrets = Array(correctedFrets.prefix(6)) }
        
        self._frets = State(initialValue: correctedFrets)
        self._fingeringForSave = State(initialValue: correctedFrets.map { $0 < 0 ? .string("x") : .int($0) })
        
        let nonZeroFrets = correctedFrets.filter { $0 > 0 }
        if let minFret = nonZeroFrets.min(), minFret > 1 {
            self._fretPosition = State(initialValue: minFret)
        } else {
            self._fretPosition = State(initialValue: 1)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("编辑和弦: \(chordName)")
                .font(.title2)
                .fontWeight(.bold)
            
            FretboardView(frets: $frets, fretPosition: $fretPosition)
            
            Stepper("把位 (Fret Position): \(fretPosition)", value: $fretPosition, in: 1...15)
            
            HStack(spacing: 12) {
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("保存") {
                    customChordManager.updateChord(name: chordName, fingering: fingeringForSave)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 600)
        .onChange(of: frets) { newFrets in
            self.fingeringForSave = newFrets.map {
                $0 < 0 ? .string("x") : .int($0)
            }
        }
    }
}

// MARK: - Preview Provider
struct CustomChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        CustomChordLibraryView()
            .environmentObject(AppData())
            .environmentObject(MidiManager())
            .environmentObject(ChordPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData()))
    }
}