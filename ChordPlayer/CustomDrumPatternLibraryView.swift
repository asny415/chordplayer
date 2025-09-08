import SwiftUI

struct CustomDrumPatternLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager
    @EnvironmentObject var drumPlayer: DrumPlayer
    
    @State private var searchText: String = ""
    @State private var showingCreateSheet = false
    @State private var patternToEdit: DrumPatternEditorData? = nil
    
    @State private var hoveredPatternID: String? = nil
    
    private var timeSignatures: [String] {
        customDrumPatternManager.customDrumPatterns.keys.sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            searchBar.padding([.horizontal, .bottom])
            Divider()
            patternList
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 700)
        .background(Color.black.opacity(0.2))
        .sheet(isPresented: $showingCreateSheet) {
            AddDrumPatternSheetView()
                .environmentObject(customDrumPatternManager)
                .environmentObject(drumPlayer)
        }
        .sheet(item: $patternToEdit) { data in
            AddDrumPatternSheetView(editingPatternData: data)
                .environmentObject(customDrumPatternManager)
                .environmentObject(drumPlayer)
        }
        .onDisappear {
            // Stop playback when the library is closed
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义鼓点库")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("管理您的专属鼓点节奏")
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
            TextField("􀊫 搜索鼓点...", text: $searchText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            
            Button(action: { showingCreateSheet = true }) {
                Label("创建新鼓点", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
        }
    }
    
    private var patternList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(timeSignatures, id: \.self) { timeSignature in
                    Section(header: Text(timeSignature).font(.headline).padding(.horizontal)) {
                        LazyVStack(spacing: 12) {
                            if let patterns = customDrumPatternManager.customDrumPatterns[timeSignature] {
                                ForEach(patterns.keys.sorted().filter { searchText.isEmpty ? true : patterns[$0]!.displayName.localizedCaseInsensitiveContains(searchText) }, id: \.self) { patternID in
                                    if let pattern = patterns[patternID] {
                                        patternCard(id: patternID, pattern: pattern, timeSignature: timeSignature)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    private func patternCard(id: String, pattern: DrumPattern, timeSignature: String) -> some View {
        let isHovered = hoveredPatternID == id
        
        return HStack(spacing: 15) {
            // 1. Replace Icon with DrumPatternGridView
            DrumPatternGridView(
                pattern: pattern,
                timeSignature: timeSignature,
                activeColor: .primary,
                inactiveColor: .secondary.opacity(0.4)
            )
            .frame(width: 120, height: 60)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("ID: \(id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: { playPreview(pattern: pattern, timeSignature: timeSignature) }) {
                    Image(systemName: drumPlayer.isPlaying && hoveredPatternID == id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("试听")
                
                Button(action: { editPattern(id: id, pattern: pattern, timeSignature: timeSignature) }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: { deletePattern(id: id, timeSignature: timeSignature) }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("删除")
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(isHovered ? 0.9 : 1.0))
        .cornerRadius(12)
        .shadow(radius: isHovered ? 4 : 1)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(.spring()) {
                hoveredPatternID = hovering ? id : nil
            }
        }
        .padding(.horizontal)
    }
    
    private func playPreview(pattern: DrumPattern, timeSignature: String) {
        if drumPlayer.isPlaying {
            drumPlayer.stop()
        } else {
            drumPlayer.play(drumPattern: pattern, timeSignature: timeSignature, bpm: 120)
        }
    }
    
    private func editPattern(id: String, pattern: DrumPattern, timeSignature: String) {
        if drumPlayer.isPlaying { drumPlayer.stop() }
        self.patternToEdit = DrumPatternEditorData(id: id, timeSignature: timeSignature, pattern: pattern)
    }
    
    private func deletePattern(id: String, timeSignature: String) {
        if drumPlayer.isPlaying { drumPlayer.stop() }
        withAnimation {
            customDrumPatternManager.deletePattern(id: id, timeSignature: timeSignature)
        }
    }
}

struct CustomDrumPatternLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = CustomDrumPatternManager.shared
        let drumPlayer = DrumPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData())
        
        manager.customDrumPatterns = [
            "4/4": [
                "ROCK_BASIC": DrumPattern(displayName: "基础摇滚", pattern: [DrumPatternEvent(delay: "0/4", notes: [36])]),
                "POP_FUNKY": DrumPattern(displayName: "流行放克", pattern: [DrumPatternEvent(delay: "0/8", notes: [36]), DrumPatternEvent(delay: "1/8", notes: [38])])
            ],
            "3/4": [
                "WALTZ": DrumPattern(displayName: "华尔兹", pattern: [])
            ]
        ]
        
        return CustomDrumPatternLibraryView()
            .environmentObject(manager)
            .environmentObject(drumPlayer)
    }
}