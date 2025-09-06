
import SwiftUI

struct ChordLibraryView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @Environment(\.dismiss) var dismiss

    /// Closure to execute when a chord is selected.
    let onAddChord: (String) -> Void
    let existingChordNames: Set<String> // Chords already in the group when the dialog opened
    @State private var sessionAddedChords: Set<String> // Chords added during this session of the dialog

    @State private var chordSearchText: String = ""

    init(onAddChord: @escaping (String) -> Void, existingChordNames: Set<String>) {
        self.onAddChord = onAddChord
        self.existingChordNames = existingChordNames
        _sessionAddedChords = State(initialValue: existingChordNames) // Initialize with existing chords
    }

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
                let results = filteredChordLibrary
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
            Text("和弦库")
                .font(.title2).bold()
            Spacer()
            
            HStack(spacing: 12) {
                Button("完成") { 
                    dismiss() 
                }
            }
        }
        .padding()
    }
    
    

    private var searchBar: some View {
        TextField("chord_library_view_search_placeholder", text: $chordSearchText)
            .textFieldStyle(.roundedBorder)
    }

    private func chordResultButton(chord: String) -> some View {
        let isCustomChord = appData.customChordManager.chordExists(name: chord)
        let isAdded = sessionAddedChords.contains(chord)
        
        return Button(action: {
            onAddChord(chord)
            sessionAddedChords.insert(chord) // Mark as added in this session
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(displayChordName(for: chord)).font(.headline)
                        if isCustomChord {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(appData.chordLibrary?[chord]?.map { item in
                        if case .string(let s) = item { return s }
                        if case .int(let i) = item { return String(i) }
                        return ""
                    }.joined(separator: "·") ?? "")
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isAdded ? Color.green.opacity(0.1) : (isCustomChord ? Color.orange.opacity(0.1) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isAdded ? Color.green.opacity(0.5) : (isCustomChord ? Color.orange.opacity(0.3) : Color.clear), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func displayChordName(for chord: String) -> String {
        let parts = chord.split(separator: "_")
        guard parts.count == 2 else {
            return chord
        }

        let note = String(parts[0])
        let quality = String(parts[1])

        switch quality {
        case "Major":
            return note
        case "Minor":
            return note + "m"
        default:
            return chord
        }
    }

    private var filteredChordLibrary: [String] {
        let allChords = Array(appData.chordLibrary?.keys ?? [String: [StringOrInt]]().keys)
        var filteredChords = allChords
        
        // 根据搜索文本过滤
        if !chordSearchText.isEmpty {
            filteredChords = filteredChords.filter { displayChordName(for: $0).localizedCaseInsensitiveContains(chordSearchText) }
        }
        
        return filteredChords.sorted()
    }
}

struct ChordLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        ChordLibraryView(onAddChord: { name in print("Added \(name)") }, existingChordNames: Set<String>())
            .environmentObject(AppData())
    }
}
