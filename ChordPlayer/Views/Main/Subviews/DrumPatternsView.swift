
import SwiftUI

struct DrumPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager

    @State private var showAddDrumPatternSheet: Bool = false
    @State private var isHoveringGroup: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("鼓点模式").font(.headline)
                Spacer()

                // Add Pattern to Workspace Button
                Button(action: { showAddDrumPatternSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .help("从库添加鼓点到工作区")
            }
            if appData.performanceConfig.selectedDrumPatterns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("当前没有鼓点模式。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加鼓点模式，或使用快捷键 ⌘1/⌘2... 进行切换")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(Array(appData.performanceConfig.selectedDrumPatterns.enumerated()), id: \.element) { index, patternId in
                        if let details = findPatternDetails(for: patternId) {
                            let isActive = appData.performanceConfig.activeDrumPatternId == patternId
                            Button(action: {
                                appData.performanceConfig.activeDrumPatternId = patternId
                                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
                            }) {
                                ZStack(alignment: .topTrailing) {
                                    DrumPatternCardView(
                                        index: index,
                                        pattern: details.pattern,
                                        category: details.category,
                                        timeSignature: appData.performanceConfig.timeSignature,
                                        isActive: isActive
                                    )

                                    if index < 9 {
                                        Text("⌘\(index + 1)")
                                            .font(.caption2).bold()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                            .offset(x: -8, y: 8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: appData.performanceConfig.activeDrumPatternId)
                            .contextMenu {
                                Button(role: .destructive) {
                                    appData.removeDrumPattern(patternId: patternId)
                                } label: {
                                    Label("移除鼓点", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringGroup = hovering
            }
        }
        .sheet(isPresented: $showAddDrumPatternSheet) {
            SelectDrumPatternsSheet(initialSelection: appData.performanceConfig.selectedDrumPatterns, onDone: { selectedIDs in
                appData.performanceConfig.selectedDrumPatterns = selectedIDs
                
                // Check if the current active pattern is still valid.
                // If not, set the first available pattern as active.
                let currentActiveId = appData.performanceConfig.activeDrumPatternId
                let isActiveIdValid = currentActiveId != nil && selectedIDs.contains(currentActiveId!)
                
                if !isActiveIdValid {
                    appData.performanceConfig.activeDrumPatternId = selectedIDs.first
                }
                
                showAddDrumPatternSheet = false
            })
            .environmentObject(appData)
            .environmentObject(customDrumPatternManager)
        }
    }

    private func findPatternDetails(for patternId: String) -> (pattern: DrumPattern, category: String)? {
        // Also check custom patterns
        for (_, patterns) in customDrumPatternManager.customDrumPatterns {
            if let pattern = patterns[patternId] {
                return (pattern, "自定义")
            }
        }

        if let library = appData.drumPatternLibrary {
            for (category, patterns) in library {
                if let pattern = patterns[patternId] {
                    return (pattern, category)
                }
            }
        }
        return nil
    }
}

struct DrumPatternCardView: View {
    let index: Int
    let pattern: DrumPattern
    let category: String
    let timeSignature: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DrumPatternGridView(
                pattern: pattern,
                timeSignature: timeSignature,
                activeColor: isActive ? .accentColor : .primary,
                inactiveColor: .secondary
            )
            .opacity(isActive ? 0.9 : 0.6)
            .padding(.trailing, 35)

            HStack {
                Text(pattern.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            HStack {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .foregroundColor(.primary)
        .padding(8)
        .frame(width: 140, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2.5 : 1)
        )
    }
}
