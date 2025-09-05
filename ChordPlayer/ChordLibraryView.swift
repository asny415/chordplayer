
import SwiftUI

struct ChordLibraryView: View {
    @EnvironmentObject var appData: AppData
    @Environment(\.dismiss) var dismiss

    /// Closure to execute when a chord is selected.
    let onAddChord: (String) -> Void

    @State private var chordSearchText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Search Bar
            searchBar
                .padding()

            // Chord Grid
            ScrollView(.vertical) {
                let results = filteredChordLibrary(prefix: chordSearchText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(results, id: \.self) { chord in
                        chordResultButton(chord: chord)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 800)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerView: some View {
        HStack {
            Text("chord_library_view_header_title")
                .font(.title2).bold()
            Spacer()
            Button("chord_library_view_cancel_button", role: .cancel) { dismiss() }
        }
        .padding()
    }

    private var searchBar: some View {
        TextField("chord_library_view_search_placeholder", text: $chordSearchText)
            .textFieldStyle(.roundedBorder)
    }

    private func chordResultButton(chord: String) -> some View {
        Button(action: { 
            onAddChord(chord)
            // Optionally dismiss after adding
            // dismiss()
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(chord).font(.headline)
                    Text(appData.chordLibrary?[chord]?.map { item in
                        if case .string(let s) = item { return s }
                        if case .int(let i) = item { return String(i) }
                        return ""
                    }.joined(separator: "·") ?? "")
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func filteredChordLibrary(prefix: String) -> [String] {
        let allChords = Array(appData.chordLibrary?.keys ?? [String: [StringOrInt]]().keys)
        if prefix.isEmpty { return allChords.sorted() }
        return allChords.filter { $0.localizedCaseInsensitiveContains(prefix) }.sorted()
    }
}

struct ChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        ChordLibraryView(onAddChord: { name in print("Added \(name)") })
            .environmentObject(AppData())
    }
}
