
import SwiftUI

struct MelodicLyricSegmentCard: View {
    @EnvironmentObject var appData: AppData
    let segment: MelodicLyricSegment
    let isActive: Bool // You might need this later to show selection
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with name
            HStack {
                Text(segment.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Stats: Length and Item count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Length")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(segment.lengthInBars) bars")
                        .font(.system(.subheadline, design: .monospaced))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(segment.items.count)")
                        .font(.system(.subheadline, design: .monospaced))
                }
            }
            
            Spacer()

            // Action buttons
            HStack {
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Edit this lyric segment")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Handle selection if needed in the future
            // onSelect()
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive) {
                showingDeleteConfirmation = true
            }
        }
        .alert("Delete \(segment.name)", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this lyric segment? This action cannot be undone.")
        }
    }
}
