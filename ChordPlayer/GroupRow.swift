import SwiftUI

// MARK: - GroupRow View
struct GroupRow: View {
    @Binding var group: PatternGroup // Changed to Binding
    var isSelected: Bool
    var onDelete: () -> Void

    @State private var isEditing: Bool = false
    @State private var editedGroupName: String = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Group Name", text: $editedGroupName, onCommit: saveChanges)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onExitCommand { // For macOS, to cancel editing
                        cancelEditing()
                    }
            } else {
                Label(group.name, systemImage: isSelected ? "folder.fill" : "folder")
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure it takes full width for double-tap
                    .contentShape(Rectangle()) // Make the whole area tappable
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
            }
        }
        .contextMenu {
            Button("Delete Group", role: .destructive, action: onDelete)
        }
        .onAppear {
            editedGroupName = group.name // Initialize when view appears
        }
    }

    private func startEditing() {
        editedGroupName = group.name
        isEditing = true
    }

    private func saveChanges() {
        if !editedGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            group.name = editedGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Optionally, revert to original name or show an alert if name is empty
            editedGroupName = group.name
        }
        isEditing = false
    }

    private func cancelEditing() {
        editedGroupName = group.name // Revert to original
        isEditing = false
    }
}
