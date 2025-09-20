
import SwiftUI

struct MelodicLyricEditorView: View {
    @Binding var segment: MelodicLyricSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Metadata Editor
            GroupBox(label: Text("Segment Settings")) {
                HStack {
                    Text("Name:")
                    TextField("Segment Name", text: $segment.name)
                }
                
                Stepper(value: $segment.lengthInBars, in: 1...64) {
                    Text("Length: \(segment.lengthInBars) bars")
                }
            }
            .padding(.horizontal)

            // Main Content Editor (Placeholder)
            GroupBox(label: Text("Lyrics Grid")) {
                Spacer()
                Text("Lyrics editing grid for a \(segment.lengthInBars)-bar segment will be implemented here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
        .background(Color(.windowBackgroundColor))
    }
}

struct MelodicLyricEditorView_Previews: PreviewProvider {
    @State static var mockSegment = MelodicLyricSegment(name: "Verse 1", lengthInBars: 4, items: [])

    static var previews: some View {
        MelodicLyricEditorView(segment: $mockSegment)
            .frame(width: 800, height: 600)
    }
}
