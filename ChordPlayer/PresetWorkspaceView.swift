import SwiftUI

/// This view acts as the main workspace for a selected preset.
/// It shows the preset's global settings and a list of its pattern groups.
struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    // The currently selected group ID.
    @Binding var activeGroupId: UUID? // Changed to UUID?

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
            if activeGroupId == nil, let firstGroup = appData.performanceConfig.patternGroups.first {
                activeGroupId = firstGroup.id
            }
            // Sync keyboard handler's active group ID with UI's active group ID
            keyboardHandler.activeGroupId = activeGroupId
        }
        .onReceive(keyboardHandler.$activeGroupId) { newId in // Listen to activeGroupId
            // Update the selection when the keyboard handler changes the group
            if newId != activeGroupId { // Only update if different to avoid loop
                activeGroupId = newId
            }
        }
        .onChange(of: appData.performanceConfig.patternGroups) { oldGroups, newGroups in
            // When the pattern groups change (e.g., a new preset is loaded),
            // activate the first group if available.
            if let firstGroup = newGroups.first {
                activeGroupId = firstGroup.id
            } else {
                activeGroupId = nil // No groups, so no active group
            }
        }
    }

    private var groupListView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("preset_workspace_chord_groups_label")
                    .font(.title2).bold()
                Spacer()
                Button(action: addGroup) {
                    Label("preset_workspace_add_group_button", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            List(selection: $activeGroupId) { // Use activeGroupId for selection
                ForEach($appData.performanceConfig.patternGroups) { $group in
                    GroupRow(
                        group: $group,
                        isSelected: group.id == activeGroupId, // Compare UUIDs
                        onDelete: { removeGroup(groupToRemove: group) } // Pass the group to remove
                    )
                    .tag(group.id) // Tag with the group's ID
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Logic
    private func addGroup() {
        let newName = String(localized: "preset_workspace_new_group_prefix") + " \(appData.performanceConfig.patternGroups.count + 1)"
        let newGroup = PatternGroup(name: newName, patterns: [:], pattern: nil, chordsOrder: [], chordAssignments: [:])
        appData.performanceConfig.patternGroups.append(newGroup)
        activeGroupId = newGroup.id // Set active group to the new group's ID
    }

    private func removeGroup(groupToRemove: PatternGroup) {
        appData.performanceConfig.patternGroups.removeAll { $0.id == groupToRemove.id }

        if activeGroupId == groupToRemove.id {
            if let firstGroup = appData.performanceConfig.patternGroups.first {
                activeGroupId = firstGroup.id
            }
        } else {
            activeGroupId = nil
        }
    }
}
