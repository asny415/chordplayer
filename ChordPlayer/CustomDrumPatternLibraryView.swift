
import SwiftUI



struct CustomDrumPatternLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager
    
    @State private var searchText: String = ""
    @State private var showingCreateSheet = false
    @State private var patternToEdit: DrumPatternEditorData? = nil
    
    // For hover effects
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
        }
        .sheet(item: $patternToEdit) { data in
            AddDrumPatternSheetView(editingPatternData: data)
                .environmentObject(customDrumPatternManager)
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
        
        return HStack { // Added return
            Image(systemName: "pianokeys")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .padding(.trailing, 8)
            
            VStack(alignment: .leading) {
                Text(pattern.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                Text("ID: \(id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button(action: { /* Play Action */ }) {
                    Image(systemName: "play.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("试听")
                
                Button(action: { editPattern(id: id, pattern: pattern, timeSignature: timeSignature) }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("编辑")
                
                Button(action: { deletePattern(id: id, timeSignature: timeSignature) }) {
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
                hoveredPatternID = hovering ? id : nil
            }
        }
        .padding(.horizontal)
    }
    
    private func editPattern(id: String, pattern: DrumPattern, timeSignature: String) {
        self.patternToEdit = DrumPatternEditorData(id: id, timeSignature: timeSignature, pattern: pattern)
    }
    
    private func deletePattern(id: String, timeSignature: String) {
        withAnimation {
            customDrumPatternManager.deletePattern(id: id, timeSignature: timeSignature)
        }
    }
}

struct CustomDrumPatternLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = CustomDrumPatternManager.shared
        // Add some dummy data for preview
        manager.customDrumPatterns = [
            "4/4": [
                "ROCK_BASIC": DrumPattern(displayName: "基础摇滚", pattern: []),
                "POP_FUNKY": DrumPattern(displayName: "流行放克", pattern: [])
            ],
            "3/4": [
                "WALTZ": DrumPattern(displayName: "华尔兹", pattern: [])
            ]
        ]
        
        return CustomDrumPatternLibraryView()
            .environmentObject(manager)
    }
}
