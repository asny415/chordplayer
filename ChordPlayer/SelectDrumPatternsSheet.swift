import SwiftUI

struct SelectDrumPatternsSheet: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager
    @Environment(\.dismiss) var dismiss
    
    var onDone: ([String]) -> Void
    
    @State private var selectedPatternIDs: Set<String>
    
    init(initialSelection: [String], onDone: @escaping ([String]) -> Void) {
        self._selectedPatternIDs = State(initialValue: Set(initialSelection))
        self.onDone = onDone
    }
    
    private var systemCategories: [String] {
        appData.drumPatternLibrary?.keys.sorted() ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("选择鼓点模式")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            
            Divider()
            
            List {
                // System Patterns
                if let library = appData.drumPatternLibrary {
                    ForEach(systemCategories.filter { $0 == appData.performanceConfig.timeSignature }, id: \.self) { category in
                        Section(header: Text(category)) {
                            ForEach(library[category]?.sorted(by: { $0.value.displayName < $1.value.displayName }) ?? [], id: \.key) { id, pattern in
                                patternSelectionRow(patternId: id, pattern: pattern, category: category)
                            }
                        }
                    }
                }
                
                // Custom Patterns
                let customPatternsByTimeSig = customDrumPatternManager.customDrumPatterns
                if !customPatternsByTimeSig.isEmpty {
                    Section(header: Text("自定义鼓点")) {
                        ForEach(customPatternsByTimeSig.keys.filter { $0 == appData.performanceConfig.timeSignature }.sorted(), id: \.self) { timeSig in
                            if let patternsDict = customPatternsByTimeSig[timeSig] {
                                ForEach(patternsDict.keys.sorted(by: { patternsDict[$0]!.displayName < patternsDict[$1]!.displayName }), id: \.self) { patternId in
                                    if let pattern = patternsDict[patternId] {
                                        patternSelectionRow(patternId: patternId, pattern: pattern, category: "自定义 (\(timeSig))")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            HStack {
                Button("取消") {
                    dismiss()
                }
                Spacer()
                Button("完成") {
                    onDone(Array(selectedPatternIDs))
                    dismiss()
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    @ViewBuilder
    private func patternSelectionRow(patternId: String, pattern: DrumPattern, category: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.displayName).font(.headline)
                DrumPatternGridView(pattern: pattern, timeSignature: appData.performanceConfig.timeSignature, activeColor: .primary, inactiveColor: .secondary)
                    .frame(height: 35)
                    .opacity(0.7)
                Text("来源: \(category)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            
            Spacer()
            
            if selectedPatternIDs.contains(patternId) {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedPatternIDs.contains(patternId) {
                selectedPatternIDs.remove(patternId)
            } else {
                selectedPatternIDs.insert(patternId)
            }
        }
    }
}

struct SelectDrumPatternsSheet_Previews: PreviewProvider {
    static var previews: some View {
        let appData = AppData()
        
        SelectDrumPatternsSheet(initialSelection: [], onDone: { _ in })
            .environmentObject(appData)
            .environmentObject(CustomDrumPatternManager.shared)
    }
}
