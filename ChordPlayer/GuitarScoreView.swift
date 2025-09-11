
import SwiftUI

// MARK: - Main Score View
struct GuitarScoreView: View {
    @EnvironmentObject var appData: AppData
    
    private let measuresPerRow = 4

    var body: some View {
        GeometryReader { geometry in
            let measures = calculateMeasures()
            let rows = measures.chunked(into: measuresPerRow)
            // Subtract horizontal padding (16*2) and measure number width (20)
            let availableWidth = geometry.size.width - 32 - 20 
            let measureWidth = availableWidth / CGFloat(measuresPerRow)
            
            VStack(alignment: .leading, spacing: 16) {
                ScoreHeaderView(
                    presetName: appData.currentPreset.name,
                    key: appData.performanceConfig.key,
                    timeSignature: appData.performanceConfig.timeSignature,
                    tempo: appData.performanceConfig.tempo
                )
                
                if measures.isEmpty {
                    Text("乐谱为空，请为和弦关联演奏指法。")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    ForEach(0..<rows.count, id: \.self) { rowIndex in
                        ScoreRowView(
                            row: rows[rowIndex],
                            startingMeasureNumber: rowIndex * measuresPerRow + 1,
                            measuresPerRow: measuresPerRow,
                            measureWidth: measureWidth
                        )
                    }
                }
            }
            .padding()
            .background(Color.white)
            .foregroundColor(.black)
        }
    }
    
    private func buildScoreEvents() -> [AutoPlayEvent] {
        var schedule: [AutoPlayEvent] = []
        let timeSignature = appData.performanceConfig.timeSignature
        var beatsPerMeasure = 4
        let timeSigParts = timeSignature.split(separator: "/")
        if timeSigParts.count == 2, let beats = Int(timeSigParts[0]) {
            beatsPerMeasure = beats
        }

        for chordConfig in appData.performanceConfig.chords {
            for (shortcut, association) in chordConfig.patternAssociations {
                if let measureIndices = association.measureIndices, !measureIndices.isEmpty {
                    for measureIndex in measureIndices {
                        let targetBeat = (measureIndex - 1) * Double(beatsPerMeasure)
                        let action = AutoPlayEvent(chordName: chordConfig.name, patternId: association.patternId, triggerBeat: Int(round(targetBeat)), shortcut: shortcut.stringValue)
                        schedule.append(action)
                    }
                }
            }
        }
        
        var finalSchedule = schedule.sorted { $0.triggerBeat < $1.triggerBeat }

        if !finalSchedule.isEmpty {
            var maxMeasure: Double = 0
            for chordConfig in appData.performanceConfig.chords {
                for (_, association) in chordConfig.patternAssociations {
                    if let measureIndices = association.measureIndices, let maxIndex = measureIndices.max() {
                        maxMeasure = max(maxMeasure, maxIndex)
                    }
                }
            }
            let totalMeasures = ceil(maxMeasure)
            let totalBeatsInLoop = Int(totalMeasures * Double(beatsPerMeasure))

            for i in 0..<finalSchedule.count {
                let currentEvent = finalSchedule[i]
                let nextTriggerBeat: Int
                if i < finalSchedule.count - 1 {
                    nextTriggerBeat = finalSchedule[i+1].triggerBeat
                } else {
                    nextTriggerBeat = totalBeatsInLoop
                }
                finalSchedule[i].durationBeats = nextTriggerBeat - currentEvent.triggerBeat
            }
        }
        return finalSchedule
    }
    
    private func calculateMeasures() -> [Measure] {
        let scoreEvents = buildScoreEvents()
        let timeSignatureParts = appData.performanceConfig.timeSignature.split(separator: "/").map { Int($0) ?? 4 }
        let beatsPerMeasure = timeSignatureParts[0]
        
        guard !scoreEvents.isEmpty, beatsPerMeasure > 0 else { return [] }
        
        let totalBeats = scoreEvents.map { $0.triggerBeat + ($0.durationBeats ?? 0) }.max() ?? 0
        let totalMeasures = Int(ceil(Double(totalBeats) / Double(beatsPerMeasure)))
        
        var measures = [Measure](repeating: Measure(chords: []), count: totalMeasures)
        
        for event in scoreEvents {
            let measureIndex = event.triggerBeat / beatsPerMeasure
            if measures.indices.contains(measureIndex) {
                let beatInMeasure = event.triggerBeat % beatsPerMeasure
                
                let chordDefinition = appData.chordLibrary?[event.chordName]
                
                let chordInMeasure = ChordInMeasure(
                    name: event.chordName,
                    beat: beatInMeasure,
                    duration: event.durationBeats ?? beatsPerMeasure,
                    definition: chordDefinition
                )
                measures[measureIndex].chords.append(chordInMeasure)
            }
        }
        
        return measures
    }
}

// ... (rest of the file is the same)


// MARK: - Sub-components
private struct ScoreHeaderView: View {
    let presetName: String
    let key: String
    let timeSignature: String
    let tempo: Double
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Key: \(key)").font(.subheadline)
                Text("Time: \(timeSignature)").font(.subheadline)
            }
            Spacer()
            Text(presetName)
                .font(.title2).bold()
            Spacer()
            Text("Tempo: \(Int(tempo)) BPM")
                .font(.subheadline)
        }
        .padding(.bottom, 8)
    }
}

private struct ScoreRowView: View {
    let row: [Measure]
    let startingMeasureNumber: Int
    let measuresPerRow: Int
    let measureWidth: CGFloat
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(startingMeasureNumber)")
                .font(.caption2)
                .frame(width: 20, alignment: .leading)
                .padding(.top, 5)
            
            ForEach(0..<row.count, id: \.self) { index in
                MeasureView(measure: row[index], measureWidth: measureWidth)
            }
            
            if row.count < measuresPerRow {
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct MeasureView: View {
    let measure: Measure
    let measureWidth: CGFloat
    
    @State private var displayedChords = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ForEach(measure.chords) { chord in
                    if !displayedChords.contains(chord.name) {
                        ChordDiagramAndNameView(chord: chord, parentWidth: measureWidth)
                            .onAppear { displayedChords.insert(chord.name) }
                    } else {
                        Text(chord.name.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
            }
            Spacer()
        }
        .padding(4)
        .frame(width: measureWidth).frame(minHeight: 80)
        .border(Color.gray, width: 0.5)
    }
}

private struct ChordDiagramAndNameView: View {
    let chord: ChordInMeasure
    let parentWidth: CGFloat
    
    var body: some View {
        VStack(spacing: 2) {
            if let definition = chord.definition {
                ChordDiagramView(frets: definition, color: .black)
                    .frame(width: parentWidth * 0.8, height: parentWidth * 0.8 * 1.2)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: parentWidth * 0.8, height: parentWidth * 0.8 * 1.2)
                    .overlay(Text("?").foregroundColor(.black))
            }
            Text(chord.name.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}


// MARK: - Data Models for Score
struct Measure: Identifiable {
    let id = UUID()
    var chords: [ChordInMeasure]
}

struct ChordInMeasure: Identifiable {
    let id = UUID()
    let name: String
    let beat: Int
    let duration: Int
    let definition: [StringOrInt]?
}

// MARK: - Utility
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview
struct GuitarScoreView_Previews: PreviewProvider {
    static var previews: some View {
        let appData = AppData()
        
        appData.performanceConfig.tempo = 120
        appData.performanceConfig.timeSignature = "4/4"
        appData.performanceConfig.key = "C"
        
        // To mimic a real preset name
        let preset = Preset(name: "My Test Song", performanceConfig: appData.performanceConfig, appConfig: appData.CONFIG)
        PresetManager.shared.currentPreset = preset

        appData.autoPlaySchedule = [
            AutoPlayEvent(chordName: "C_Major", patternId: "p1", triggerBeat: 0, durationBeats: 4, shortcut: "c"),
            AutoPlayEvent(chordName: "G_Major", patternId: "p1", triggerBeat: 4, durationBeats: 4, shortcut: "g"),
            AutoPlayEvent(chordName: "Am", patternId: "p1", triggerBeat: 8, durationBeats: 4, shortcut: "a"),
            AutoPlayEvent(chordName: "F_Major", patternId: "p1", triggerBeat: 12, durationBeats: 4, shortcut: "f"),
            AutoPlayEvent(chordName: "C_Major", patternId: "p1", triggerBeat: 16, durationBeats: 2, shortcut: "c"),
            AutoPlayEvent(chordName: "G_Major", patternId: "p1", triggerBeat: 18, durationBeats: 2, shortcut: "g"),
        ]
        
        if let lib = DataLoader.load(filename: "chords", as: ChordLibrary.self) {
            appData.chordLibrary = lib
        }

        return ScrollView {
            GuitarScoreView()
                .environmentObject(appData)
        }
        .background(Color.gray.opacity(0.3))
    }
}
