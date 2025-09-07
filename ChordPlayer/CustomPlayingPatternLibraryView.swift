
import SwiftUI



struct CustomPlayingPatternLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    
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
        }
        .sheet(item: $patternToEdit) { data in
            PlayingPatternEditorView(editingPatternData: data)
                .environmentObject(customPlayingPatternManager)
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
            VStack(alignment: .leading, spacing: 16) {
                ForEach(timeSignatures, id: \.self) { timeSignature in
                    Section(header: Text(timeSignature).font(.headline).padding(.horizontal)) {
                        LazyVStack(spacing: 12) {
                            if let patterns = customPlayingPatternManager.customPlayingPatterns[timeSignature] {
                                ForEach(patterns.filter { searchText.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(searchText) }) { pattern in
                                    patternCard(pattern: pattern, timeSignature: timeSignature)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    private func patternCard(pattern: GuitarPattern, timeSignature: String) -> some View {
        let isHovered = hoveredPatternID == pattern.id
        
        return HStack { // Added return
            Image(systemName: "guitars") // Icon for playing patterns
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)
            
            VStack(alignment: .leading) {
                Text(pattern.name)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("ID: \(pattern.id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Button(action: { /* Play Action */ }) {
                    Image(systemName: "play.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("试听")
                
                Button(action: { editPattern(pattern: pattern, timeSignature: timeSignature) }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: { deletePattern(id: pattern.id, timeSignature: timeSignature) }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("删除")
            }
            .font(.body)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(isHovered ? 0.9 : 1.0))
        .cornerRadius(12)
        .shadow(radius: isHovered ? 6 : 1)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.spring()) {
                hoveredPatternID = hovering ? pattern.id : nil
            }
        }
        .padding(.horizontal)
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
        let manager = CustomPlayingPatternManager.shared
        manager.customPlayingPatterns = [
            "4/4": [
                GuitarPattern(id: "4-4-arpeggio", name: "基础分解", pattern: []),
                GuitarPattern(id: "4-4-strum", name: "基础扫弦", pattern: [])
            ],
            "3/4": [
                GuitarPattern(id: "3-4-waltz", name: "华尔兹分解", pattern: [])
            ]
        ]
        
        return CustomPlayingPatternLibraryView()
            .environmentObject(manager)
    }
}
