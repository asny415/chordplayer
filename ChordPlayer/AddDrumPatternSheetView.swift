import SwiftUI

struct AddDrumPatternSheetView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss

    @State private var selectedPatternIds: Set<String> = []
    @State private var availablePatterns: [String: [(String, DrumPattern)]] = [:] // Store patterns grouped by category with their IDs
    
    var body: some View {
        VStack(spacing: 0) {
            Text("添加鼓点模式")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            
            Divider()
            
            List {
                ForEach(availablePatterns.keys.sorted(), id: \.self) { category in
                    Section(header: Text(category)) {
                        ForEach(availablePatterns[category] ?? [], id: \.0) { patternId, drumPattern in // Use .0 for patternId as ID
                            Button(action: {
                                if selectedPatternIds.contains(patternId) {
                                    selectedPatternIds.remove(patternId)
                                } else {
                                    selectedPatternIds.insert(patternId)
                                }
                            }) {
                                HStack {
                                    Text(drumPattern.displayName)
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
        guard let drumLibrary = appData.drumPatternLibrary else { return }
        
        var patternsGroupedByCategory: [String: [(String, DrumPattern)]] = [:]
        let currentSelectedIds = Set(appData.performanceConfig.selectedDrumPatterns)
        
        for (category, patternsById) in drumLibrary {
            for (patternId, drumPattern) in patternsById {
                // Only add patterns not already selected in the current preset
                if !currentSelectedIds.contains(patternId) {
                    patternsGroupedByCategory[category, default: []].append((patternId, drumPattern))
                }
            }
        }
        self.availablePatterns = patternsGroupedByCategory
    }
    
    private func addSelectedPatterns() {
        // Append new patterns to the existing selectedDrumPatterns
        appData.performanceConfig.selectedDrumPatterns.append(contentsOf: Array(selectedPatternIds))
        // Optionally, set the first newly added pattern as active
        if let firstNewId = selectedPatternIds.first {
            appData.performanceConfig.activeDrumPatternId = firstNewId
        }
    }
}
