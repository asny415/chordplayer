import SwiftUI

// MARK: - Main Segment Card View

struct SegmentCardView<Content: View>: View {
    let title: String
    let systemImageName: String
    let isSelected: Bool
    @ViewBuilder let content: Content

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: systemImageName)
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }

            // Content
            content
        }
        .padding(12)
        .background(
            backgroundStyle
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .onHover { hovering in
            withAnimation(.spring()) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        let roundedRect = RoundedRectangle(cornerRadius: 12)
        
        ZStack {
            // Frosted glass background
            roundedRect
                .fill(.ultraThinMaterial)

            // Selection/Hover highlight
            if isSelected {
                roundedRect
                    .stroke(Color.accentColor, lineWidth: 3)
            } else if isHovering {
                roundedRect
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            }
        }
    }
}

// MARK: - Accompaniment Content

struct AccompanimentCardContent: View {
    let segment: AccompanimentSegment
    let preset: Preset

    private var chordProgression: String {
        let chordNames = segment.measures
            .flatMap { $0.chordEvents }
            .sorted { $0.startBeat < $1.startBeat }
            .compactMap { event in
                preset.chords.first { $0.id == event.resourceId }?.name
            }
            .removingDuplicates()
        
        return chordNames.isEmpty ? "No chords" : chordNames.prefix(4).joined(separator: " → ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chordProgression)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Image(systemName: "music.note.list")
                Text("\(segment.lengthInMeasures) Bars")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Melodic Lyric Content

struct MelodicLyricCardContent: View {
    let segment: MelodicLyricSegment

    private var lyricsPreview: String {
        let preview = segment.items
            .map { $0.word }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return preview.isEmpty ? "No lyrics" : preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\"\(lyricsPreview)\"")
                .font(.body)
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.tail)
            
            HStack(spacing: 4) {
                Image(systemName: "music.mic")
                Text("\(segment.lengthInBars) Bars")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - Previews

#if DEBUG
struct SegmentCardView_Previews: PreviewProvider {
    static let mockAccompanimentSegment = AccompanimentSegment(name: "Verse A", lengthInMeasures: 4)
    static let mockMelodicSegment = MelodicLyricSegment(name: "Chorus Melody", lengthInBars: 4, items: [
        MelodicLyricItem(word: "This", positionInTicks: 0, pitch: 1, octave: 0),
        MelodicLyricItem(word: "is", positionInTicks: 3, pitch: 2, octave: 0),
        MelodicLyricItem(word: "a", positionInTicks: 6, pitch: 3, octave: 0),
        MelodicLyricItem(word: "test", positionInTicks: 9, pitch: 4, octave: 0),
        MelodicLyricItem(word: "lyric", positionInTicks: 12, pitch: 5, octave: 0)
    ])
    static let mockPreset = Preset.createNew(name: "Mock Preset")

    static var previews: some View {
        VStack(spacing: 20) {
            // Accompaniment Card Preview
            SegmentCardView(
                title: mockAccompanimentSegment.name,
                systemImageName: "guitars",
                isSelected: false
            ) {
                AccompanimentCardContent(segment: mockAccompanimentSegment, preset: mockPreset)
            }
            
            // Selected Accompaniment Card
            SegmentCardView(
                title: mockAccompanimentSegment.name,
                systemImageName: "guitars",
                isSelected: true
            ) {
                AccompanimentCardContent(segment: mockAccompanimentSegment, preset: mockPreset)
            }

            // Melodic Lyric Card Preview
            SegmentCardView(
                title: mockMelodicSegment.name,
                systemImageName: "music.mic",
                isSelected: false
            ) {
                MelodicLyricCardContent(segment: mockMelodicSegment)
            }
            
            // Selected Melodic Lyric Card
            SegmentCardView(
                title: mockMelodicSegment.name,
                systemImageName: "music.mic",
                isSelected: true
            ) {
                MelodicLyricCardContent(segment: mockMelodicSegment)
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color.gray.opacity(0.1))
    }
}
#endif