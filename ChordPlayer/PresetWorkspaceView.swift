import SwiftUI
import AppKit

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
            // Key selector with shortcut badge (- / =)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "调性",
                    selection: $appData.performanceConfig.key,
                    options: appData.KEY_CYCLE
                )
                .frame(maxWidth: .infinity)

                Text("-/=")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Time signature selector with shortcut badge (T)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "拍号",
                    selection: $appData.performanceConfig.timeSignature,
                    options: appData.TIME_SIGNATURE_CYCLE
                )
                .frame(maxWidth: .infinity)

                Text("T")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Tempo card with arrow badge (↑/↓)
            ZStack(alignment: .topTrailing) {
                TempoDashboardCard(tempo: $appData.performanceConfig.tempo)
                    .frame(maxWidth: .infinity)

                Text("↑/↓")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Quantize selector with badge (Q)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "量化",
                    selection: Binding<QuantizationMode>(
                        get: { QuantizationMode(rawValue: appData.performanceConfig.quantize ?? "NONE") ?? .none },
                        set: { appData.performanceConfig.quantize = $0.rawValue }
                    ),
                    options: QuantizationMode.allCases
                )
                .frame(maxWidth: .infinity)

                Text("Q")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            ZStack(alignment: .topTrailing) {
                DrumMachineStatusCard()
                    .frame(maxWidth: .infinity)

                Text("P")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }
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
            Spacer()

            HStack {
                Text(pattern.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            HStack {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
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
                            ZStack(alignment: .topTrailing) {
                                DrumPatternCardView(
                                    index: index,
                                    pattern: details.pattern,
                                    category: details.category,
                                    isActive: isActive
                                )

                                if index < 9 {
                                    Text("⌘\(index + 1)")
                                        .font(.caption2).bold()
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                        .offset(x: -8, y: 8)
                                }
                            }
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
    let category: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()

            HStack {
                Text(pattern.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            HStack {
                Text(category)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
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
                            ZStack(alignment: .topTrailing) {
                                PlayingPatternCardView(
                                    index: index,
                                    pattern: details.pattern,
                                    category: details.category,
                                    isActive: isActive
                                )

                                if index < 9 {
                                    Text("\(index + 1)")
                                        .font(.caption2).bold()
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                                        .offset(x: -8, y: 8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: appData.performanceConfig.activePlayingPatternId)
                    }
                }
            }
            .padding(1)
        }
    }
    
    private func findPlayingPatternDetails(for patternId: String) -> (pattern: GuitarPattern, category: String)? {
        guard let library = appData.patternLibrary else { return nil }
        for (category, patterns) in library {
            if let pattern = patterns.first(where: { $0.id == patternId }) {
                return (pattern, category)
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
            Text(displayChordName(for: chord))
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

    private func displayChordName(for chord: String) -> String {
        // Handle names like "C_Sharp_Major", "A_Minor", "C_Sharp_7", etc.
        let components = chord.split(separator: "_")
        guard components.count >= 2 else { return chord.replacingOccurrences(of: "_Sharp", with: "#") }

        let quality = String(components.last!)
        let noteParts = components.dropLast()
        let noteRaw = noteParts.joined(separator: "_") // e.g. "C" or "C_Sharp"
        let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")

        switch quality {
        case "Major":
            return noteDisplay
        case "Minor":
            return noteDisplay + "m"
        default:
            // Full name: replace _Sharp -> # and remove other underscores so "C_Sharp_7" -> "C#7"
            return chord.replacingOccurrences(of: "_Sharp", with: "#").replacingOccurrences(of: "_", with: "")
        }
    }
}

private struct ChordProgressionView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var flashingChord: String? = nil
    @State private var showAddChordSheet: Bool = false
    @State private var capturingChord: String? = nil
    @State private var captureMonitor: Any? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("和弦进行").font(.headline)
                Spacer()
                Button(action: { showAddChordSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                ForEach(appData.performanceConfig.chords, id: \.self) { chord in
                    // local values
                    let parts = chord.split(separator: "_")

                    ZStack(alignment: .topTrailing) {
                        ChordCardView(chord: chord, isFlashing: flashingChord == chord)
                            .animation(.easeInOut(duration: 0.15), value: flashingChord)

                        // Shortcut badge (custom or default). Always show a Text badge.
                        let (badgeText, badgeColor): (String, Color) = {
                            // 1) user-assigned shortcut
                            if let preset = PresetManager.shared.currentPreset, let s = preset.chordShortcuts[chord] {
                                return (s.displayText, Color.accentColor)
                            }

                            // 2) fallback to sensible default mapping for simple single-letter notes
                            let components = chord.split(separator: "_")
                            if components.count >= 2 {
                                let quality = String(components.last!)
                                let noteParts = components.dropLast()
                                let noteRaw = noteParts.joined(separator: "_")
                                let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")

                                if noteDisplay.count == 1 {
                                    if quality == "Major" {
                                        return (noteDisplay.uppercased(), Color.gray.opacity(0.6))
                                    } else if quality == "Minor" {
                                        return ("⇧\(noteDisplay.uppercased())", Color.gray.opacity(0.6))
                                    }
                                }
                            }

                            // 3) otherwise show a marker indicating the user can set a shortcut
                            // 使用单字标记以保持徽章简洁（假设为中文环境，使用“设”表示“设置快捷键”）
                            return ("+", Color.gray.opacity(0.6))
                        }()

                        // Badge button: tapping this starts capturing a new shortcut for this chord.
                        Button(action: {
                            captureShortcutForChord(chord: chord)
                        }) {
                            Text(badgeText)
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(badgeColor, in: RoundedRectangle(cornerRadius: 6))
                                .offset(x: -8, y: 8)
                        }
                        .buttonStyle(.plain)
                    }
                    // Tapping anywhere else on the card plays the chord
                    .onTapGesture {
                        keyboardHandler.playChordByName(chord)
                    }
                }
            }
        }
        .overlay(
            Group {
                if capturingChord != nil {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 12) {
                            Text("Press a key to assign shortcut")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Press Esc to cancel")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .padding(24)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .transition(.opacity)
                }
            }
        )

        .onReceive(keyboardHandler.$lastPlayedChord) { chord in
            guard let chord = chord else { return }
            flashingChord = chord
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                flashingChord = nil
            }
        }
        .sheet(isPresented: $showAddChordSheet) {
            ChordLibraryView(onAddChord: { chordName in
                appData.performanceConfig.chords.append(chordName)
            }, existingChordNames: Set(appData.performanceConfig.chords))
        }
    }

    private func captureShortcutForChord(chord: String) {
        // start capturing
        capturingChord = chord
        // Temporarily pause the global keyboard handler so it doesn't intercept
        // the key event we're trying to capture.
        keyboardHandler.pauseEventMonitoring()

        // add local monitor to capture next keyDown
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape key to cancel
            if event.keyCode == 53 {
                if let m = captureMonitor { NSEvent.removeMonitor(m) }
                captureMonitor = nil
                capturingChord = nil
                // restore global handler
                keyboardHandler.resumeEventMonitoring()
                return nil
            }

            if let s = Shortcut.from(event: event) {
                PresetManager.shared.setShortcut(s, forChord: chord)
            }

            if let m = captureMonitor { NSEvent.removeMonitor(m) }
            captureMonitor = nil
            capturingChord = nil
            // restore global handler
            keyboardHandler.resumeEventMonitoring()
            return nil
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