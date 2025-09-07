import SwiftUI

struct AddPlayingPatternSheetView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss

    @State private var selectedPatternIds: Set<String> = []
    @State private var availablePatterns: [String: [(String, GuitarPattern)]] = [:] // Store patterns grouped by category with their IDs
    
    var body: some View {
        VStack(spacing: 0) {
            Text("添加和弦指法")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            
            Divider()
            
            List {
                ForEach(availablePatterns.keys.sorted(), id: \.self) { category in
                    Section(header: Text(category)) {
                        ForEach(availablePatterns[category] ?? [], id: \.0) { patternId, guitarPattern in // Use .0 for patternId as ID
                            Button(action: {
                                if selectedPatternIds.contains(patternId) {
                                    selectedPatternIds.remove(patternId)
                                } else {
                                    selectedPatternIds.insert(patternId)
                                }
                            }) {
                                HStack {
                                    Text(guitarPattern.name)
                                    Spacer()
                                    if selectedPatternIds.contains(patternId) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func loadAvailablePatterns() {
        guard let patternLibrary = appData.patternLibrary else { return }
        
        var patternsGroupedByCategory: [String: [(String, GuitarPattern)]] = [:]
        let currentSelectedIds = Set(appData.performanceConfig.selectedPlayingPatterns)
        
        for (category, patternsArray) in patternLibrary {
            for guitarPattern in patternsArray {
                // Only add patterns not already selected in the current preset
                if !currentSelectedIds.contains(guitarPattern.id) {
                    patternsGroupedByCategory[category, default: []].append((guitarPattern.id, guitarPattern))
                }
            }
        }
        self.availablePatterns = patternsGroupedByCategory
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
