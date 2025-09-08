import SwiftUI

struct SelectDrumPatternsSheet: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager
    @Environment(\.presentationMode) var presentationMode
    
    var onDone: ([String]) -> Void
    
    @State private var selectedPatternIDs: Set<String> = []
    
    private var systemCategories: [String] {
        appData.drumPatternLibrary?.keys.sorted() ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("从库中选择鼓点模式")
                    .font(.title2).bold()
                Spacer()
                Button("完成") {
                    onDone(Array(selectedPatternIDs))
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .frame(height: 55)

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
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 700)
    }
    
    @ViewBuilder
    private func patternSelectionRow(patternId: String, pattern: DrumPattern, category: String) -> some View {
        Toggle(isOn: Binding<Bool>(
            get: { self.selectedPatternIDs.contains(patternId) },
            set: { isOn in
                if isOn {
                    self.selectedPatternIDs.insert(patternId)
                } else {
                    self.selectedPatternIDs.remove(patternId)
                }
            }
        )) {
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
        }
        .toggleStyle(.switch)
    }
}