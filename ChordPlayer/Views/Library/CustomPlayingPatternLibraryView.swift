
import SwiftUI



struct CustomPlayingPatternLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var appData: AppData
    
    @State private var searchText: String = ""
    @State private var showingCreateSheet = false
    @State private var patternToEdit: PlayingPatternEditorData? = nil
    
    @State private var hoveredPatternID: String? = nil

    private var timeSignatures: [String] {
        customPlayingPatternManager.customPlayingPatterns.keys.sorted()
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
            PlayingPatternEditorView()
                .environmentObject(customPlayingPatternManager)
                .environmentObject(appData)
        }
        .sheet(item: $patternToEdit) { data in
            PlayingPatternEditorView(editingPatternData: data)
                .environmentObject(customPlayingPatternManager)
                .environmentObject(appData)
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义演奏模式库")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("管理您的分解和弦与扫弦节奏")
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
            TextField("􀊫 搜索模式...", text: $searchText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
            
            Button(action: { showingCreateSheet = true }) {
                Label("创建新模式", systemImage: "plus")
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
                    if let patterns = customPlayingPatternManager.customPlayingPatterns[timeSignature] {
                        let filteredPatterns = patterns.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }
                        
                        if !filteredPatterns.isEmpty {
                            Text(timeSignature)
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.top)
                                .gridCellUnsizedAxes(.horizontal)

                            ForEach(filteredPatterns) { pattern in
                                patternCard(pattern: pattern, timeSignature: timeSignature)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func patternCard(pattern: GuitarPattern, timeSignature: String) -> some View {
        let isHovered = hoveredPatternID == pattern.id
        
        return VStack(spacing: 12) {
            Text(pattern.name)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)

            PlayingPatternView(
                pattern: pattern,
                timeSignature: timeSignature,
                color: .primary
            )
            .opacity(0.8)
            .frame(height: 50)
            .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button(action: { playPreview(pattern: pattern) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("试听")
                
                Button(action: { editPattern(pattern: pattern, timeSignature: timeSignature) }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: { deletePattern(id: pattern.id, timeSignature: timeSignature) }) {
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
                hoveredPatternID = hovering ? pattern.id : nil
                if !hovering {
                    if !hovering {
                    // Stop playback when mouse leaves
                    chordPlayer.panic()
                }
                }
            }
        }
    }
    
    private func playPreview(pattern: GuitarPattern) {
        // Use a default C chord for previewing the pattern
        chordPlayer.playChord(chordName: "C_Major", pattern: pattern, tempo: 120, key: "C", capo: 0, velocity: 100, duration: 4.0)
    }
    
    private func editPattern(pattern: GuitarPattern, timeSignature: String) {
        self.patternToEdit = PlayingPatternEditorData(id: pattern.id, timeSignature: timeSignature, pattern: pattern)
    }
    
    private func deletePattern(id: String, timeSignature: String) {
        withAnimation {
            customPlayingPatternManager.deletePattern(id: id, timeSignature: timeSignature)
        }
    }
}

struct CustomPlayingPatternLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        let customPlayingPatternManager = CustomPlayingPatternManager.shared
        let customChordManager = CustomChordManager.shared
        let appData = AppData(customChordManager: customChordManager)
        let midiManager = MidiManager()
        let chordPlayer = ChordPlayer(midiManager: midiManager, appData: appData)

        customPlayingPatternManager.customPlayingPatterns = [
            "4/4": [
                GuitarPattern(id: "4-4-arpeggio", name: "基础分解", pattern: []),
                GuitarPattern(id: "4-4-strum", name: "基础扫弦", pattern: [])
            ],
            "3/4": [
                GuitarPattern(id: "3-4-waltz", name: "华尔兹分解", pattern: [])
            ]
        ]
        
        return CustomPlayingPatternLibraryView()
            .environmentObject(customPlayingPatternManager)
            .environmentObject(chordPlayer)
            .environmentObject(appData)
    }
}
