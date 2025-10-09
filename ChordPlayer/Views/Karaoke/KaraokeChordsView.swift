
import SwiftUI

/// A model to hold processed chord information for easy rendering.
struct ChordDisplayInfo: Identifiable, Hashable {
    let id = UUID()
    let chord: Chord
    let startBeat: Double // Global start beat in the arrangement
    let durationInBeats: Double
}

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
    
    var body: some View {
        let currentMeasureIndex = floor(playbackPosition / beatsPerMeasure)
        let currentMeasureStartBeat = currentMeasureIndex * beatsPerMeasure
        let nextMeasureStartBeat = (currentMeasureIndex + 1) * beatsPerMeasure
        
        let currentMeasureChords = allChords.filter {
            $0.startBeat >= currentMeasureStartBeat && $0.startBeat < nextMeasureStartBeat
        }
        
        let nextMeasureChords = allChords.filter {
            $0.startBeat >= nextMeasureStartBeat && $0.startBeat < (nextMeasureStartBeat + beatsPerMeasure)
        }

        GeometryReader { geometry in
            let timelineHeight: CGFloat = 100
            let totalWidth = geometry.size.width * 0.8
            let measureWidth = totalWidth / 2
            
            let progressInMeasure = (playbackPosition - currentMeasureStartBeat) / beatsPerMeasure
            let playheadX = measureWidth * CGFloat(progressInMeasure)

            HStack(spacing: 0) {
                MeasureChordsView(
                    chords: currentMeasureChords,
                    measureStartBeat: currentMeasureStartBeat,
                    beatsPerMeasure: beatsPerMeasure,
                    isCurrent: true
                )
                .frame(width: measureWidth)
                
                MeasureChordsView(
                    chords: nextMeasureChords,
                    measureStartBeat: nextMeasureStartBeat,
                    beatsPerMeasure: beatsPerMeasure,
                    isCurrent: false
                )
                .frame(width: measureWidth)
            }
            .frame(width: totalWidth, height: timelineHeight)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
            .overlay(
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2)
                    .offset(x: playheadX)
                , alignment: .leading
            )
            .frame(maxWidth: .infinity)
        }
        .frame(height: 120)
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

private struct MeasureChordsView: View {
    let chords: [ChordDisplayInfo]
    let measureStartBeat: Double
    let beatsPerMeasure: Double
    let isCurrent: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(isCurrent ? Color.gray.opacity(0.4) : Color.gray.opacity(0.2))
                
                Path { path in
                    for i in 1..<Int(beatsPerMeasure) {
                        let x = (CGFloat(i) / CGFloat(beatsPerMeasure)) * geometry.size.width
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: 8))
                    }
                }
                .stroke(isCurrent ? Color.white.opacity(0.5) : Color.white.opacity(0.3), lineWidth: 1)
                .frame(height: 8)

                ForEach(chords) { chordInfo in
                    let chordStartInMeasure = chordInfo.startBeat - measureStartBeat
                    let xPosition = (chordStartInMeasure / beatsPerMeasure) * geometry.size.width
                    
                    VStack(spacing: 2) {
                        Text(chordInfo.chord.name)
                            .font(.caption)
                            .foregroundColor(isCurrent ? .white : .gray)
                            .padding(.horizontal, 4)
                            .background(isCurrent ? Color.blue.opacity(0.7) : Color.gray.opacity(0.5))
                            .cornerRadius(4)
                        
                        ChordDiagramView(chord: chordInfo.chord, color: isCurrent ? .white : .gray)
                            .frame(width: 60, height: 70)
                    }
                    .offset(x: xPosition)
                }
            }
        }
        .clipped()
    }
}
