import SwiftUI

/// A model to hold processed chord information for easy rendering.
struct ChordDisplayInfo: Identifiable, Hashable {
    let id = UUID()
    let chord: Chord
    let startBeat: Double // Global start beat in the arrangement
    let durationInBeats: Double
}

// MARK: - New Simplified, Uniquely Named Subviews

/// A simple horizontal line with tick marks for the Karaoke view, with a highlighted active section.
private struct KaraokeTimelineRuler: View {
    let beatsPerMeasure: Double
    let measureCount: Int
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let measureWidth = totalWidth / CGFloat(measureCount)
            
            // Draw the second, inactive part of the ruler first
            Path { path in
                path.move(to: CGPoint(x: measureWidth, y: 0))
                path.addLine(to: CGPoint(x: totalWidth, y: 0))
                
                // Ticks for the second measure
                for i in 1...Int(beatsPerMeasure) {
                    let beatWidth = measureWidth / CGFloat(beatsPerMeasure)
                    let x = measureWidth + (CGFloat(i) * beatWidth)
                    path.move(to: CGPoint(x: x, y: -2))
                    path.addLine(to: CGPoint(x: x, y: 2))
                }
                path.move(to: CGPoint(x: totalWidth, y: -4))
                path.addLine(to: CGPoint(x: totalWidth, y: 4))
            }
            .stroke(Color.gray.opacity(0.7), lineWidth: 1)

            // Draw the first, active part of the ruler
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: measureWidth, y: 0))
                
                // Ticks for the first measure
                for i in 0...Int(beatsPerMeasure) {
                    let beatWidth = measureWidth / CGFloat(beatsPerMeasure)
                    let x = CGFloat(i) * beatWidth
                    path.move(to: CGPoint(x: x, y: -2))
                    path.addLine(to: CGPoint(x: x, y: 2))
                }
                path.move(to: CGPoint(x: 0, y: -4))
                path.addLine(to: CGPoint(x: 0, y: 4))
                path.move(to: CGPoint(x: measureWidth, y: -4))
                path.addLine(to: CGPoint(x: measureWidth, y: 4))
            }
            .stroke(Color.cyan, lineWidth: 1.5) // Use a distinct color and slightly thicker line
        }
        .frame(height: 10)
    }
}

/// A small triangle playhead indicator that points upwards.
private struct KaraokePlayheadIndicator: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 5, y: 0)) // The tip
            path.addLine(to: CGPoint(x: 10, y: 8)) // Bottom-right
            path.addLine(to: CGPoint(x: 0, y: 8)) // Bottom-left
            path.closeSubpath()
        }
        .fill(Color.yellow)
        .frame(width: 10, height: 8)
        .shadow(color: .black.opacity(0.4), radius: 2, y: -1)
    }
}


// MARK: - Main Karaoke Chords View

struct KaraokeChordsView: View {
    @EnvironmentObject var appData: AppData
    let playbackPosition: Double
    let arrangement: SongArrangement
    
    @State private var allChords: [ChordDisplayInfo] = []
    
    private var timeSignature: TimeSignature {
        appData.preset?.timeSignature ?? TimeSignature()
    }
    
    private var beatsPerMeasure: Double {
        Double(timeSignature.beatsPerMeasure)
    }
    
    private func chords(forMeasureStartingAt measureStartBeat: Double) -> [ChordDisplayInfo] {
        var chordsInMeasure = allChords.filter {
            $0.startBeat >= measureStartBeat && $0.startBeat < (measureStartBeat + beatsPerMeasure)
        }
        
        let hasChordOnFirstBeat = chordsInMeasure.contains { $0.startBeat == measureStartBeat }
        
        if !hasChordOnFirstBeat {
            if let carryOverChord = allChords.last(where: { $0.startBeat < measureStartBeat }) {
                let carriedOverInfo = ChordDisplayInfo(
                    chord: carryOverChord.chord,
                    startBeat: measureStartBeat,
                    durationInBeats: carryOverChord.durationInBeats
                )
                chordsInMeasure.insert(carriedOverInfo, at: 0)
            }
        }
        
        return chordsInMeasure
    }
    
    var body: some View {
        let currentMeasureIndex = floor(playbackPosition / beatsPerMeasure)
        let currentMeasureStartBeat = currentMeasureIndex * beatsPerMeasure
        let nextMeasureStartBeat = (currentMeasureIndex + 1) * beatsPerMeasure
        
        let currentMeasureChords = chords(forMeasureStartingAt: currentMeasureStartBeat)
        let nextMeasureChords = chords(forMeasureStartingAt: nextMeasureStartBeat)

        GeometryReader { geometry in
            let totalWidth = geometry.size.width * 0.8
            let measureWidth = totalWidth / 2
            
            let progressInMeasure = (playbackPosition - currentMeasureStartBeat) / beatsPerMeasure
            let playheadX = measureWidth * CGFloat(progressInMeasure)

            VStack(spacing: 0) {
                // The two measures of chords
                HStack(spacing: 0) {
                    MeasureChordsView(
                        chords: currentMeasureChords,
                        measureStartBeat: currentMeasureStartBeat,
                        beatsPerMeasure: beatsPerMeasure
                    )
                    .frame(width: measureWidth)
                    
                    MeasureChordsView(
                        chords: nextMeasureChords,
                        measureStartBeat: nextMeasureStartBeat,
                        beatsPerMeasure: beatsPerMeasure
                    )
                    .frame(width: measureWidth)
                }
                .frame(width: totalWidth)
                .padding(.bottom, 4) // Space for the playhead triangle
                
                // New Timeline Ruler and Playhead
                ZStack(alignment: .topLeading) {
                    KaraokeTimelineRuler(beatsPerMeasure: beatsPerMeasure, measureCount: 2)
                        .frame(width: totalWidth)
                    
                    KaraokePlayheadIndicator()
                        .offset(x: playheadX - 5) // Center the triangle on the line
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 155) // Adjusted height for larger diagrams
        .onAppear(perform: updateChordData)
        .onChange(of: arrangement) { _ in updateChordData() }
    }
    
    private func updateChordData() {
        guard let preset = appData.preset else { self.allChords = []; return }
        
        guard let track = arrangement.guitarTracks.first(where: { track in
            track.segments.contains(where: { segment in
                if case .accompaniment = segment.type { return true }
                return false
            })
        }) else {
            self.allChords = []
            return
        }

        var chordInfos: [ChordDisplayInfo] = []
        
        for segment in track.segments {
            if case .accompaniment(let segmentId) = segment.type {
                if let accomSegment = preset.accompanimentSegments.first(where: { $0.id == segmentId }) {
                    for (measureIndex, measure) in accomSegment.measures.enumerated() {
                        for chordEvent in measure.chordEvents {
                            if let chord = preset.chords.first(where: { $0.id == chordEvent.resourceId }) {
                                let globalStartBeat = segment.startBeat + (Double(measureIndex) * beatsPerMeasure) + Double(chordEvent.startBeat)
                                let info = ChordDisplayInfo(
                                    chord: chord,
                                    startBeat: globalStartBeat,
                                    durationInBeats: Double(chordEvent.durationInBeats)
                                )
                                chordInfos.append(info)
                            }
                        }
                    }
                }
            }
        }
        self.allChords = chordInfos.sorted { $0.startBeat < $1.startBeat }
    }
}

// MARK: - Simplified Measure Chords View

private struct MeasureChordsView: View {
    let chords: [ChordDisplayInfo]
    let measureStartBeat: Double
    let beatsPerMeasure: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                ForEach(chords) { chordInfo in
                    let chordStartInMeasure = chordInfo.startBeat - measureStartBeat
                    let clampedStart = max(0, chordStartInMeasure)
                    let xPosition = (clampedStart / beatsPerMeasure) * geometry.size.width
                    
                    VStack {
                        ChordDiagramView(chord: chordInfo.chord, color: .primary)
                            .frame(width: 100, height: 117) // Increased size again
                    }
                    .offset(x: xPosition)
                }
            }
        }
        .clipped()
    }
}
