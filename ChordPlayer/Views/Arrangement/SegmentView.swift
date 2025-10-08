
import SwiftUI

struct SegmentView: View {
    // Display properties
    let text: String
    let color: Color
    
    // Layout properties
    let startBeat: Double
    let durationInBeats: Double
    let pixelsPerBeat: CGFloat
    
    // Interaction
    let onMove: (Double) -> Void // Closure to call when the segment is moved
    var onRemove: (() -> Void)? = nil // Optional closure for removing the segment
    
    // State for tracking the drag gesture
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.7))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .clipped()
        }
        .frame(width: pixelsPerBeat * durationInBeats, height: 48)
        // The final position is the sum of the original position and the temporary drag offset
        .offset(x: (pixelsPerBeat * startBeat) + dragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    // Update the temporary drag offset during the drag
                    self.dragOffset = gesture.translation.width
                }
                .onEnded { gesture in
                    // When the drag ends, calculate the new beat position
                    let beatOffset = gesture.translation.width / pixelsPerBeat
                    let newStartBeat = startBeat + beatOffset
                    
                    // Snap to the nearest whole beat
                    let snappedBeat = round(newStartBeat)
                    
                    // Call the provided closure to update the data model
                    onMove(snappedBeat)
                    
                    // Reset the temporary drag offset
                    self.dragOffset = 0
                }
        )
        .contextMenu {
            if let onRemove = onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
