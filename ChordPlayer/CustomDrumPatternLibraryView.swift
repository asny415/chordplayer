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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 20)], spacing: 20) {
                ForEach(timeSignatures, id: \.self) { timeSignature in
                    if let patterns = customDrumPatternManager.customDrumPatterns[timeSignature] {
                        let filteredPatterns = patterns.keys.sorted().filter { searchText.isEmpty ? true : patterns[$0]!.displayName.localizedCaseInsensitiveContains(searchText) }
                        
                        if !filteredPatterns.isEmpty {
                            Text(timeSignature)
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.top)
                                .gridCellUnsizedAxes(.horizontal)

                            ForEach(filteredPatterns, id: \.self) { patternID in
                                if let pattern = patterns[patternID] {
                                    patternCard(id: patternID, pattern: pattern, timeSignature: timeSignature)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func patternCard(id: String, pattern: DrumPattern, timeSignature: String) -> some View {
        let isHovered = hoveredPatternID == id
        
        return VStack(spacing: 12) {
            Text(pattern.displayName)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)

            DrumPatternGridView(
                pattern: pattern,
                timeSignature: timeSignature,
                activeColor: .primary,
                inactiveColor: .secondary.opacity(0.4)
            )
            .frame(height: 60)
            .padding(.horizontal)
            
            HStack(spacing: 20) {
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
        .padding(15)
        .background(Color(NSColor.windowBackgroundColor).opacity(isHovered ? 0.9 : 1.0))
        .cornerRadius(16)
        .shadow(radius: isHovered ? 5 : 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring()) {
                hoveredPatternID = hovering ? id : nil
                if !hovering && drumPlayer.isPlaying {
                    drumPlayer.stop()
                }
            }
        }
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
        let drumPlayer = DrumPlayer(midiManager: MidiManager(), appData: AppData())
        
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