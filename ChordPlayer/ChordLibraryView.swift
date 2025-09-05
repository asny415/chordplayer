
import SwiftUI

struct ChordLibraryView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @Environment(\.dismiss) var dismiss

    /// Closure to execute when a chord is selected.
    let onAddChord: (String) -> Void

    @State private var chordSearchText: String = ""
    @State private var selectedTab: ChordLibraryTab = .all
    @State private var showingCustomChordCreator = false
    @State private var showingCustomChordManager = false
    
    enum ChordLibraryTab: String, CaseIterable {
        case all = "全部"
        case builtIn = "内置"
        case custom = "自定义"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab Picker
            tabPicker
                .padding(.horizontal)

            // Search Bar
            searchBar
                .padding()

            // Chord Grid
            ScrollView(.vertical) {
                let results = filteredChordLibrary(prefix: chordSearchText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(results, id: \.self) { chord in
                        chordResultButton(chord: chord)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 800)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingCustomChordCreator) {
            CustomChordCreatorView()
                .environmentObject(appData)
                .environmentObject(chordPlayer)
                .environmentObject(keyboardHandler)
        }
        .sheet(isPresented: $showingCustomChordManager) {
            CustomChordLibraryView()
                .environmentObject(appData)
                .environmentObject(chordPlayer)
        }
    }

    private var headerView: some View {
        HStack {
            Text("和弦库")
                .font(.title2).bold()
            Spacer()
            
            HStack(spacing: 12) {
                Button("创建自定义和弦") {
                    showingCustomChordCreator = true
                }
                .buttonStyle(.bordered)
                
                Button("管理自定义和弦") {
                    showingCustomChordManager = true
                }
                .buttonStyle(.bordered)
                
                Button("取消", role: .cancel) { 
                    dismiss() 
                }
            }
        }
        .padding()
    }
    
    private var tabPicker: some View {
        Picker("和弦类型", selection: $selectedTab) {
            ForEach(ChordLibraryTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchBar: some View {
        TextField("chord_library_view_search_placeholder", text: $chordSearchText)
            .textFieldStyle(.roundedBorder)
    }

    private func chordResultButton(chord: String) -> some View {
        let isCustomChord = appData.customChordManager.chordExists(name: chord)
        
        return Button(action: { 
            onAddChord(chord)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(chord).font(.headline)
                        if isCustomChord {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(appData.chordLibrary?[chord]?.map { item in
                        if case .string(let s) = item { return s }
                        if case .int(let i) = item { return String(i) }
                        return ""
                    }.joined(separator: "·") ?? "")
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCustomChord ? Color.orange.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCustomChord ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func filteredChordLibrary(prefix: String) -> [String] {
        let allChords = Array(appData.chordLibrary?.keys ?? [String: [StringOrInt]]().keys)
        var filteredChords = allChords
        
        // 根据选中的标签页过滤
        switch selectedTab {
        case .all:
            filteredChords = allChords
        case .builtIn:
            filteredChords = allChords.filter { !appData.customChordManager.chordExists(name: $0) }
        case .custom:
            filteredChords = allChords.filter { appData.customChordManager.chordExists(name: $0) }
        }
        
        // 根据搜索文本过滤
        if !prefix.isEmpty {
            filteredChords = filteredChords.filter { $0.localizedCaseInsensitiveContains(prefix) }
        }
        
        return filteredChords.sorted()
    }
}

struct ChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        ChordLibraryView(onAddChord: { name in print("Added \(name)") })
            .environmentObject(AppData())
    }
}
