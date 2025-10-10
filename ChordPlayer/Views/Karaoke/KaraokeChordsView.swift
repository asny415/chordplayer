import SwiftUI

/// A model to hold processed chord information for easy rendering.
struct ChordDisplayInfo: Identifiable, Hashable {
    let id = UUID()
    let chord: Chord
    let startBeat: Double // Global start beat in the arrangement
    let durationInBeats: Double
}


/// A dynamic, animated timeline for the Karaoke view, drawn with lines.
private struct DynamicKaraokeRulerView: View {
    let playbackPosition: Double
    let beatsPerMeasure: Double
    private let measureCount = 2
    private let lineWidth: CGFloat = 2.0 // Define line width for consistency

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let measureWidth = totalWidth / CGFloat(measureCount)
            
            // Calculate progress within the current measure (0.0 to 1.0)
            let progressInMeasure = (playbackPosition / beatsPerMeasure).truncatingRemainder(dividingBy: 1.0)
            let progressWidth = measureWidth * progressInMeasure

            ZStack(alignment: .leading) {
                // Layer 1: Background Line
                // Gray line for the entire length
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: totalWidth, y: 0))
                }
                .stroke(Color.gray.opacity(0.5), lineWidth: lineWidth)

                // Layer 2: Animated Progress Line (Subtle Green)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: progressWidth, y: 0))
                }
                .stroke(Color.green.opacity(0.6), lineWidth: lineWidth)
                .animation(.linear, value: progressInMeasure) // Key to smoothness

                // Layer 3: Ticks (drawn on top of all lines)
                Path { path in
                    for i in 0...measureCount {
                        let x = CGFloat(i) * measureWidth
                        path.move(to: CGPoint(x: x, y: -4))
                        path.addLine(to: CGPoint(x: x, y: 4))
                    }
                    for i in 0..<(Int(beatsPerMeasure) * measureCount) {
                        let beatWidth = measureWidth / CGFloat(beatsPerMeasure)
                        let x = CGFloat(i) * beatWidth
                        path.move(to: CGPoint(x: x, y: -2))
                        path.addLine(to: CGPoint(x: x, y: 2))
                    }
                }
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
        }
        .frame(height: 10)
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

            VStack(spacing: 8) {
                // The two measures of chords
                HStack(spacing: 0) {
                    MeasureChordsView(
                        chords: currentMeasureChords,
                        measureStartBeat: currentMeasureStartBeat,
                        beatsPerMeasure: beatsPerMeasure,
                        alpha: 1.0
                    )
                    .frame(width: measureWidth)
                    
                    MeasureChordsView(
                        chords: nextMeasureChords,
                        measureStartBeat: nextMeasureStartBeat,
                        beatsPerMeasure: beatsPerMeasure,
                        alpha: 0.5
                    )
                    .frame(width: measureWidth)
                }
                .frame(width: totalWidth)
                
                // Dynamic animated Timeline Ruler
                DynamicKaraokeRulerView(
                    playbackPosition: playbackPosition,
                    beatsPerMeasure: beatsPerMeasure
                )
                .frame(width: totalWidth)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 175)
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
    let alpha: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                ForEach(chords) { chordInfo in
                    let chordStartInMeasure = chordInfo.startBeat - measureStartBeat
                    let clampedStart = max(0, chordStartInMeasure)
                    let xPosition = (clampedStart / beatsPerMeasure) * geometry.size.width
                    
                    // The VStack and Text are removed. ChordDiagramView is now the only view here.
                    ChordDiagramView(chord: chordInfo.chord, color: .primary, showName: true, alpha: alpha)
                        .frame(width: 100, height: 140)
                        .offset(x: xPosition)
                }
            }
        }
        .clipped()
    }
}