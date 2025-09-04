import SwiftUI

// MARK: - GroupRow View
struct GroupRow: View {
    var group: PatternGroup
    var isSelected: Bool
    var onDelete: () -> Void

    var body: some View {
        Label(group.name, systemImage: isSelected ? "folder.fill" : "folder")
            .contextMenu {
                Button("Delete Group", role: .destructive, action: onDelete)
            }
    }
}
