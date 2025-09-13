import SwiftUI

struct AddPlayingPatternSheetView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager
    @Environment(\.dismiss) var dismiss

    @State private var showingCreateSheet = false

    @State private var selectedPatternIds: Set<String> = []
    @State private var availablePatterns: [(id: String, pattern: GuitarPattern)] = []
    
    var body: some View {
        VStack(spacing: 0) {
            Text("添加和弦指法")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            
            Divider()
            
            List {
                ForEach(availablePatterns, id: \.id) { patternInfo in
                    Button(action: {
                        if selectedPatternIds.contains(patternInfo.id) {
                            selectedPatternIds.remove(patternInfo.id)
                        } else {
                            selectedPatternIds.insert(patternInfo.id)
                        }
                    }) {
                        HStack(spacing: 15) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(patternInfo.pattern.name)
                                    .font(.headline)
                                PlayingPatternView(
                                    pattern: patternInfo.pattern,
                                    timeSignature: appData.performanceConfig.timeSignature,
                                    color: .primary
                                )
                                .frame(height: 40)
                            }
                            
                            Spacer()
                            
                            if selectedPatternIds.contains(patternInfo.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear(perform: loadAvailablePatterns)
            .sheet(isPresented: $showingCreateSheet, onDismiss: loadAvailablePatterns) {
                PlayingPatternEditorView(globalTimeSignature: appData.performanceConfig.timeSignature)
                    .environmentObject(customPlayingPatternManager)
                    .environmentObject(chordPlayer)
                    .environmentObject(midiManager)
            }
            
            Divider()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                Button("创建新模式") {
                    showingCreateSheet = true
                }.buttonStyle(.bordered)
                Spacer()
                Button("添加 (\(selectedPatternIds.count))") {
                    addSelectedPatterns()
                    dismiss()
                }
                .disabled(selectedPatternIds.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
    }
    
    private func loadAvailablePatterns() {
        let currentTimeSignature = appData.performanceConfig.timeSignature
        
        // Get system patterns
        let systemPatterns = appData.patternLibrary?[currentTimeSignature] ?? []
        
        // Get custom patterns
        let customPatterns = customPlayingPatternManager.customPlayingPatterns[currentTimeSignature] ?? []
        
        // Combine and remove duplicates (prefer custom if IDs conflict)
        let allPatterns = (customPatterns + systemPatterns).reduce(into: [String: GuitarPattern]()) { result, pattern in
            result[pattern.id] = result[pattern.id] ?? pattern
        }.values.sorted(by: { $0.name < $1.name })
        
        let currentSelectedIds = Set(appData.performanceConfig.selectedPlayingPatterns)
        
        self.availablePatterns = allPatterns
            .filter { !currentSelectedIds.contains($0.id) }
            .map { (id: $0.id, pattern: $0) }
    }
    
    private func addSelectedPatterns() {
        // Append new patterns to the existing selectedPlayingPatterns
        appData.performanceConfig.selectedPlayingPatterns.append(contentsOf: Array(selectedPatternIds))
        
        // After adding, check if the active ID is still valid. If not, set the first available one.
        let fullList = appData.performanceConfig.selectedPlayingPatterns
        let currentActiveId = appData.performanceConfig.activePlayingPatternId
        let isActiveIdValid = currentActiveId != nil && fullList.contains(currentActiveId!)

        if !isActiveIdValid {
            appData.performanceConfig.activePlayingPatternId = fullList.first
        }
    }
}
