import SwiftUI

/// 自定义和弦管理界面
struct CustomChordLibraryView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var midiManager: MidiManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var customChordManager = CustomChordManager.shared
    
    @State private var searchText: String = ""
    @State private var selectedChords: Set<String> = []
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var showingCreateSheet = false // New state for creating new chord
    @State private var editingChordName: String = ""
    @State private var editingFingering: [StringOrInt] = []
    
    var body: some View {
        NavigationView { // Re-introducing NavigationView
            VStack(spacing: 0) {
                // 标题栏
                headerView
                
                Divider()
                
                // 搜索栏
                searchBar
                    .padding()
                
                // 工具栏
                toolbar
                    .padding(.horizontal)
                
                Divider()
                
                // 和弦网格
                chordGrid
            }
            // Removed .frame(maxWidth: .infinity, maxHeight: .infinity) from VStack
            // Removed .background(Color(NSColor.windowBackgroundColor)) from VStack
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 500, idealHeight: 700) // Apply frame to NavigationView
        .background(Color(NSColor.windowBackgroundColor)) // Apply background to NavigationView
        .alert("删除和弦", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteSelectedChords()
            }
        } message: {
            Text("确定要删除选中的 \(selectedChords.count) 个和弦吗？此操作无法撤销。")
        }
        .sheet(isPresented: $showingEditSheet) {
            CustomChordEditorView(
                chordName: editingChordName,
                initialFingering: editingFingering
            )
        }
        .sheet(isPresented: $showingCreateSheet) {
            CustomChordCreatorView()
                .environmentObject(appData)
                .environmentObject(chordPlayer)
                .environmentObject(midiManager)
        }
    }
    
    // MARK: - 子视图
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义和弦管理")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("管理您的自定义和弦库")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("创建新和弦") {
                    showCreateChord()
                }
                .buttonStyle(.borderedProminent)
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索和弦名称...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var toolbar: some View {
        HStack {
            Text("\(filteredChords.count) 个和弦")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if !selectedChords.isEmpty {
                HStack(spacing: 8) {
                    Button("编辑") {
                        editSelectedChord()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedChords.count != 1)
                    
                    Button("删除") {
                        showingDeleteAlert = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private var chordGrid: some View {
        Group {
            if filteredChords.isEmpty {
                VStack {
                    Spacer()
                    Text("您还没有创建任何自定义和弦。")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)
                    Text("请通过菜单栏的 '文件' -> '创建自定义和弦...' 来添加。")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredChords, id: \.self) { chordName in
                            chordCard(chordName: chordName)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private func chordCard(chordName: String) -> some View {
        let fingering = customChordManager.customChords[chordName] ?? []
        let isSelected = selectedChords.contains(chordName)
        
        return VStack(spacing: 12) {
            // 和弦名称
            HStack {
                Text(chordName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: { playChord(chordName) }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            // 指法图
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { stringIndex in
                    let value = fingering[stringIndex]
                    Text(fingeringDisplayText(value))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
            }
            
            // 操作按钮
            HStack(spacing: 8) {
                Button("编辑") {
                    editChord(chordName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("删除") {
                    deleteChord(chordName)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 2 : 1)
                )
        )
        .onTapGesture {
            toggleSelection(chordName)
        }
    }
    
    // MARK: - 计算属性
    
    private var filteredChords: [String] {
        let chords = customChordManager.customChordNames
        if searchText.isEmpty {
            return chords
        }
        return chords.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - 操作方法
    
    private func showCreateChord() {
        showingCreateSheet = true
    }
    
    private func playChord(_ chordName: String) {
        
        if let pattern = appData.patternLibrary?[appData.performanceConfig.timeSignature]?.first {
            chordPlayer.playChord(
                chordName: chordName,
                pattern: pattern,
                tempo: appData.performanceConfig.tempo,
                key: appData.performanceConfig.key,
                capo: 0,
                velocity: 100,
                duration: 1.0
            )
        }
    }
    
    private func toggleSelection(_ chordName: String) {
        if selectedChords.contains(chordName) {
            selectedChords.remove(chordName)
        } else {
            selectedChords.insert(chordName)
        }
    }
    
    private func editSelectedChord() {
        guard let chordName = selectedChords.first else { return }
        editChord(chordName)
    }
    
    private func editChord(_ chordName: String) {
        editingChordName = chordName
        editingFingering = customChordManager.customChords[chordName] ?? []
        showingEditSheet = true
    }
    
    private func deleteChord(_ chordName: String) {
        customChordManager.deleteChord(name: chordName)
        selectedChords.remove(chordName)
    }
    
    private func deleteSelectedChords() {
        for chordName in selectedChords {
            customChordManager.deleteChord(name: chordName)
        }
        selectedChords.removeAll()
    }
    
    private func fingeringDisplayText(_ value: StringOrInt) -> String {
        switch value {
        case .string("x"):
            return "×"
        case .int(let fret):
            return "\(fret)"
        case .string(let s):
            return s
        }
    }
}

// MARK: - 和弦编辑器
struct CustomChordEditorView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var customChordManager = CustomChordManager.shared
    
    let chordName: String
    
    // States for the new FretboardView
    @State private var frets: [Int]
    @State private var fretPosition: Int = 1
    
    // Legacy state for saving, kept in sync
    @State private var fingeringForSave: [StringOrInt]
    
    init(chordName: String, initialFingering: [StringOrInt]) {
        self.chordName = chordName
        
        // Initialize the states upon creation
        let initialFrets = initialFingering.map { item -> Int in
            switch item {
            case .int(let fret):
                return fret
            default:
                return -1 // "x" or other strings become -1
            }
        }
        self._frets = State(initialValue: initialFrets)
        self._fingeringForSave = State(initialValue: initialFingering)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("编辑和弦: \(chordName)")
                .font(.title2)
                .fontWeight(.bold)
            
            // Use the new, modern FretboardView
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
            // Keep the saving model in sync with the editor state
            self.fingeringForSave = newFrets.map {
                $0 < 0 ? .string("x") : .int($0)
            }
        }
    }
}

// MARK: - 预览
struct CustomChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        CustomChordLibraryView()
            .environmentObject(AppData())
    }
}
