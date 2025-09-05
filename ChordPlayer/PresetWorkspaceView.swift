
import SwiftUI

/// This view acts as the main workspace for a selected preset.
/// It shows the preset's global settings and a list of its pattern groups.
struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    // The currently selected group index. This will be passed to the detail view.
    @Binding var activeGroupIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Global Preset Controls
            // We will move the contents of ControlBarView here.
            // For now, it's a placeholder.
            ControlBarView()
                .padding()

            Divider()

            // MARK: - Group List
            groupListView
        }
        .background(Color.black.opacity(0.1))
        .onAppear {
            // Ensure a group is selected if possible
            if activeGroupIndex == nil, !appData.performanceConfig.patternGroups.isEmpty {
                activeGroupIndex = 0
            }
        }
        .onReceive(keyboardHandler.$currentGroupIndex) { newIndex in
            // Update the selection when the keyboard handler changes the group
            if appData.performanceConfig.patternGroups.indices.contains(newIndex) {
                activeGroupIndex = newIndex
            }
        }
    }

    private var groupListView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Chord Groups")
                    .font(.title2).bold()
                Spacer()
                Button(action: addGroup) {
                    Label("Add Group", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            List(selection: $activeGroupIndex) {
                ForEach(Array(appData.performanceConfig.patternGroups.indices), id: \.self) { index in
                    GroupRow(
                        group: appData.performanceConfig.patternGroups[index],
                        isSelected: index == activeGroupIndex,
                        onDelete: { removeGroup(at: index) }
                    )
                    .tag(index)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Logic
    private func addGroup() {
        let newName = "New Group \(appData.performanceConfig.patternGroups.count + 1)"
        let newGroup = PatternGroup(name: newName, patterns: [:], pattern: nil, chordAssignments: [:])
        appData.performanceConfig.patternGroups.append(newGroup)
        activeGroupIndex = appData.performanceConfig.patternGroups.count - 1
    }

    private func removeGroup(at index: Int) {
        guard appData.performanceConfig.patternGroups.indices.contains(index) else { return }
        appData.performanceConfig.patternGroups.remove(at: index)

        if activeGroupIndex == index {
            if appData.performanceConfig.patternGroups.isEmpty {
                activeGroupIndex = nil
            } else if index >= appData.performanceConfig.patternGroups.count {
                activeGroupIndex = appData.performanceConfig.patternGroups.count - 1
            } else {
                // The selection will automatically move to the next item or stay if it's the last one
                // No change needed to activeGroupIndex if it's not the last one
            }
        } else if let currentActive = activeGroupIndex, currentActive > index {
            activeGroupIndex = currentActive - 1
        }
    }
}

// Note: The GroupRow view is already defined in GroupConfigPanelView.swift.
// For this to compile, we would need to move GroupRow to its own file or
// redefine it here. For now, we assume it's accessible.
// If we get a build error, moving GroupRow will be the first step.
