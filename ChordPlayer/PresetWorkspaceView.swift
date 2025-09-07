import SwiftUI

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    GlobalSettingsView()
                }
                
                GroupBox(label: Text("鼓点模式 (Cmd + 1, 2...)").font(.headline)) {
                    DrumPatternsView()
                }

                GroupBox(label: Text("和弦指法 (1, 2...)").font(.headline)) {
                    PlayingPatternsView()
                }

                GroupBox {
                    ChordProgressionView()
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Custom Control Views

private struct DashboardCardView: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))

            if let unit = unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct TempoDashboardCard: View {
    @Binding var tempo: Double
    @State private var startTempo: Double? = nil

    var body: some View {
        DashboardCardView(label: "速度", value: "\(Int(round(tempo)))", unit: "BPM")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if self.startTempo == nil {
                            self.startTempo = self.tempo
                        }
                        let dragAmount = value.translation.width
                        let newTempo = self.startTempo! + Double(dragAmount / 4.0)
                        self.tempo = max(40, min(240, newTempo))
                    }
                    .onEnded { _ in
                        self.tempo = round(self.tempo)
                        self.startTempo = nil
                    }
            )
    }
}

private struct DraggableValueCard<T: Equatable & CustomStringConvertible>: View {
    let label: String
    @Binding var selection: T
    let options: [T]
    
    @State private var startIndex: Int? = nil

    var body: some View {
        DashboardCardView(label: label, value: selection.description)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard let currentIndex = options.firstIndex(of: selection) else { return }
                        if self.startIndex == nil {
                            self.startIndex = currentIndex
                        }
                        
                        let dragAmount = value.translation.width
                        let indexOffset = Int(round(dragAmount / 30.0)) // Drag sensitivity
                        
                        let newIndex = self.startIndex! + indexOffset
                        let clampedIndex = max(0, min(options.count - 1, newIndex))
                        
                        self.selection = options[clampedIndex]
                    }
                    .onEnded { _ in
                        self.startIndex = nil
                    }
            )
    }
}

// MARK: - Main Views

private struct GlobalSettingsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer
    
    var body: some View {
        HStack(spacing: 12) {
            DraggableValueCard(
                label: "调性",
                selection: $appData.performanceConfig.key,
                options: appData.KEY_CYCLE
            )
            .frame(maxWidth: .infinity)

            DraggableValueCard(
                label: "拍号",
                selection: $appData.performanceConfig.timeSignature,
                options: appData.TIME_SIGNATURE_CYCLE
            )
            .frame(maxWidth: .infinity)

            TempoDashboardCard(tempo: $appData.performanceConfig.tempo)
                .frame(maxWidth: .infinity)

            DraggableValueCard(
                label: "量化",
                selection: Binding<QuantizationMode>(
                    get: { QuantizationMode(rawValue: appData.performanceConfig.quantize ?? "NONE") ?? .none },
                    set: { appData.performanceConfig.quantize = $0.rawValue }
                ),
                options: QuantizationMode.allCases
            )
            .frame(maxWidth: .infinity)
            
            DrumMachineStatusCard() // Add this line
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }
}

private struct DrumMachineStatusCard: View {
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var appData: AppData // Needed for tempo for playPattern

    var body: some View {
        DashboardCardView(
            label: "鼓机", // "Drum Machine"
            value: drumPlayer.isPlaying ? "运行中" : "停止" // "Running" : "Stopped"
        )
        .onTapGesture {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            } else {
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(drumPlayer.isPlaying ? Color.green : Color.secondary.opacity(0.2), lineWidth: drumPlayer.isPlaying ? 2.5 : 1)
        )
    }
}

private struct DrumPatternCardView: View {
    let index: Int
    let pattern: DrumPattern
    let category: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Color.black.opacity(0.3), in: Circle())
                Spacer()
            }
            
            Spacer()

            Text(pattern.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(category)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(8)
        .frame(width: 140, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2.5 : 1)
        )
    }
}

private struct DrumPatternsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(appData.performanceConfig.selectedDrumPatterns.enumerated()), id: \.element) { index, patternId in
                    if let details = findPatternDetails(for: patternId) {
                        let isActive = appData.performanceConfig.activeDrumPatternId == patternId
                        Button(action: {
                            appData.performanceConfig.activeDrumPatternId = patternId
                            drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
                        }) {
                            DrumPatternCardView(
                                index: index,
                                pattern: details.pattern,
                                category: details.category,
                                isActive: isActive
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: appData.performanceConfig.activeDrumPatternId)
                    }
                }
            }
            .padding(1)
        }
    }

    private func findPatternDetails(for patternId: String) -> (pattern: DrumPattern, category: String)? {
        guard let library = appData.drumPatternLibrary else { return nil }
        for (category, patterns) in library {
            if let pattern = patterns[patternId] {
                return (pattern, category)
            }
        }
        return nil
    }
}

private struct PlayingPatternCardView: View {
    let index: Int
    let pattern: GuitarPattern
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Color.black.opacity(0.3), in: Circle())
                Spacer()
            }
            
            Spacer()

            Text(pattern.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // You can add more details here if needed, e.g., pattern.id or a summary of pattern.events
            // Text(pattern.id)
            //     .font(.caption)
            //     .foregroundColor(.secondary)
        }
        .foregroundColor(.primary)
        .padding(8)
        .frame(width: 140, height: 80)
        .background(isActive ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2.5 : 1)
        )
    }
}

private struct PlayingPatternsView: View {
    @EnvironmentObject var appData: AppData

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(appData.performanceConfig.selectedPlayingPatterns.enumerated()), id: \.element) { index, patternId in
                    if let details = findPlayingPatternDetails(for: patternId) {
                        let isActive = appData.performanceConfig.activePlayingPatternId == patternId
                        Button(action: {
                            appData.performanceConfig.activePlayingPatternId = patternId
                        }) {
                            PlayingPatternCardView(
                                index: index,
                                pattern: details,
                                isActive: isActive
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: appData.performanceConfig.activePlayingPatternId)
                    }
                }
            }
            .padding(1)
        }
    }
    
    private func findPlayingPatternDetails(for patternId: String) -> GuitarPattern? {
        guard let library = appData.patternLibrary else { return nil }
        for (_, patterns) in library {
            if let pattern = patterns.first(where: { $0.id == patternId }) {
                return pattern
            }
        }
        return nil
    }
}

private struct ChordCardView: View {
    let chord: String
    let isFlashing: Bool

    var body: some View {
        VStack(alignment: .center) {
            Text(chord)
                .font(.title3.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(.primary)
        .frame(width: 140, height: 80)
        .background(isFlashing ? Material.thick : Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFlashing ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isFlashing ? 2.5 : 1)
        )
    }
}

private struct ChordProgressionView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var flashingChord: String? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("和弦进行").font(.headline)
                Spacer()
                Button(action: { /* Add chord action */ }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                ForEach(appData.performanceConfig.chords, id: \.self) { chord in
                    ChordCardView(chord: chord, isFlashing: flashingChord == chord)
                        .animation(.easeInOut(duration: 0.15), value: flashingChord)
                }
            }
        }
        .onReceive(keyboardHandler.$lastPlayedChord) { chord in
            guard let chord = chord else { return }
            flashingChord = chord
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                flashingChord = nil
            }
        }
    }
}



extension QuantizationMode: CustomStringConvertible {
    public var description: String { self.displayName }
}

extension Binding where Value == String? {
    var bound: Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? "" },
            set: { self.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}