import SwiftUI

struct AddPlayingPatternSheetView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss

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
            
            Divider()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
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
        guard let patternLibrary = appData.patternLibrary else { return }
        
        let currentTimeSignature = appData.performanceConfig.timeSignature
        let patternsForCurrentTS = patternLibrary[currentTimeSignature] ?? []
        
        let currentSelectedIds = Set(appData.performanceConfig.selectedPlayingPatterns)
        
        self.availablePatterns = patternsForCurrentTS
            .filter { !currentSelectedIds.contains($0.id) }
            .map { (id: $0.id, pattern: $0) }
    }
    
    private func addSelectedPatterns() {
        // Append new patterns to the existing selectedPlayingPatterns
        appData.performanceConfig.selectedPlayingPatterns.append(contentsOf: Array(selectedPatternIds))
        // Optionally, set the first newly added pattern as active
        if let firstNewId = selectedPatternIds.first {
            appData.performanceConfig.activePlayingPatternId = firstNewId
        }
    }
}
