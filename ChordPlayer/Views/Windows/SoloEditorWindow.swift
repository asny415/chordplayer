import SwiftUI

struct SoloEditorWindow: View {
    @EnvironmentObject var appData: AppData
    @State private var selectedSegment: SoloSegment?
    @State private var showingCreateDialog = false
    @State private var newSegmentName = ""
    @State private var newSegmentLength: Double = 4.0
    
    var body: some View {
        NavigationSplitView {
            // 左侧Solo列表
            SoloLibraryView(
                selectedSegment: $selectedSegment,
                onCreateNew: {
                    newSegmentName = "New Solo \(soloSegments.count + 1)"
                    newSegmentLength = 4.0
                    showingCreateDialog = true
                },
                onDelete: deleteSoloSegment
            )
            .frame(minWidth: 250, maxWidth: 350)
        } detail: {
            // 右侧编辑器
            if let segment = selectedSegment,
               let segmentBinding = bindingForSegment(segment.id) {
                SoloEditorView(soloSegment: segmentBinding)
                    .navigationTitle(segment.name)
                    .toolbar(content: {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Save") {
                                appData.saveChanges()
                            }
                        }
                    })
                    .environmentObject(appData)
            } else {
                VStack {
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select a solo to edit")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Choose from the list or create a new solo")
                        .foregroundColor(Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingCreateDialog) {
            CreateSoloDialog(
                name: $newSegmentName,
                length: $newSegmentLength,
                onCreate: { name, length in
                    createNewSolo(name: name, length: length)
                    showingCreateDialog = false
                },
                onCancel: {
                    showingCreateDialog = false
                }
            )
        }
        .onAppear {
            // 如果没有选中的Solo，默认选择第一个
            if selectedSegment == nil && !soloSegments.isEmpty {
                selectedSegment = soloSegments.first
            }
        }
    }
    
    private var soloSegments: [SoloSegment] {
        appData.preset?.soloSegments ?? []
    }
    
    private func bindingForSegment(_ id: UUID) -> Binding<SoloSegment>? {
        guard let index = soloSegments.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { appData.preset?.soloSegments[index] ?? SoloSegment() },
            set: { appData.preset?.soloSegments[index] = $0 }
        )
    }
    
    private func createNewSolo(name: String, length: Double) {
        let newSegment = SoloSegment(name: name, lengthInBeats: length)
        appData.preset?.soloSegments.append(newSegment)
        selectedSegment = newSegment
        appData.saveChanges()
    }
    
    private func deleteSoloSegment(_ segment: SoloSegment) {
        if let index = soloSegments.firstIndex(where: { $0.id == segment.id }) {
            appData.preset?.soloSegments.remove(at: index)
            if selectedSegment?.id == segment.id {
                selectedSegment = soloSegments.first
            }
            appData.saveChanges()
        }
    }
}

struct SoloLibraryView: View {
    @EnvironmentObject var appData: AppData
    @Binding var selectedSegment: SoloSegment?
    let onCreateNew: () -> Void
    let onDelete: (SoloSegment) -> Void
    
    private var soloSegments: [SoloSegment] {
        appData.preset?.soloSegments ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("Solo Library")
                    .font(.headline)
                Spacer()
                Button(action: onCreateNew) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create new solo")
            }
            .padding()
            
            Divider()
            
            // Solo列表
            if soloSegments.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No solos yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Click + to create your first solo")
                            .foregroundColor(Color.secondary)
                        
                        Button("Create Solo", action: onCreateNew)
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(soloSegments, selection: $selectedSegment) { segment in
                    SoloListItem(
                        segment: segment,
                        isSelected: selectedSegment?.id == segment.id,
                        onSelect: { selectedSegment = segment },
                        onDelete: { onDelete(segment) }
                    )
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SoloListItem: View {
    let segment: SoloSegment
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text("\(String(format: "%.1f", segment.lengthInBeats)) beats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(segment.notes.count) notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Rename") {
                // TODO: 实现重命名功能
            }
            
            Button("Duplicate") {
                // TODO: 实现复制功能
            }
            
            Divider()
            
            Button("Delete", role: .destructive, action: onDelete)
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
}

struct CreateSoloDialog: View {
    @Binding var name: String
    @Binding var length: Double
    let onCreate: (String, Double) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create New Solo")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Enter the details for your new solo segment")
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.headline)
                    TextField("Solo name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Length (beats)")
                        .font(.headline)
                    
                    HStack {
                        Slider(value: $length, in: 1...16, step: 0.5) {
                            Text("Length")
                        }
                        .frame(maxWidth: .infinity)
                        
                        Text("\(String(format: "%.1f", length))")
                            .frame(width: 40)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Create") {
                    onCreate(name, length)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// 窗口管理器
@MainActor
class SoloEditorWindowManager: ObservableObject {
    private var window: NSWindow?
    private weak var appData: AppData?
    
    func setAppData(_ appData: AppData) {
        self.appData = appData
    }
    
    func openSoloEditor() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        guard let appData = appData else { return }
        
        let contentView = SoloEditorWindow()
            .environmentObject(appData)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Solo Editor"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        
        // 设置最小窗口大小
        newWindow.minSize = NSSize(width: 800, height: 600)
        
        self.window = newWindow
    }
    
    func closeSoloEditor() {
        window?.close()
        window = nil
    }
}