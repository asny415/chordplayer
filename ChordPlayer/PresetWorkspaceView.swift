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
                
                GroupBox {
                    DrumPatternsView()
                }

                GroupBox {
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
        ZStack(alignment: .bottomTrailing) {
            DashboardCardView(label: "速度", value: "\(Int(round(tempo)))", unit: "BPM")
            
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(5)
        }
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
        ZStack(alignment: .bottomTrailing) {
            DashboardCardView(label: label, value: selection.description)
            
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(5)
        }
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

private struct PlayingModeBadgeView: View {
    let playingMode: String
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(playingMode.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.15))
                    )
                
                if index < playingMode.count - 1 {
                    Text("|")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
    }
}

private struct DrumMachineStatusCard: View {
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var appData: AppData

    var body: some View {
        VStack(spacing: 4) {
            Text("演奏".uppercased())
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .center, spacing: 10) {
                PlayingModeBadgeView(playingMode: appData.playingMode.shortDisplay)
                
                Text(drumPlayer.isPlaying ? "运行中" : "停止")
                    .font(.system(.title, design: .rounded).weight(.bold))
            }
            .foregroundColor(drumPlayer.isPlaying ? .green : .primary)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    let timeSignature: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DrumPatternGridView(
                pattern: pattern,
                timeSignature: timeSignature,
                activeColor: isActive ? .accentColor : .primary,
                inactiveColor: .secondary
            )
            .opacity(isActive ? 0.9 : 0.6)
            .padding(.trailing, 35)

            HStack {
                Text(pattern.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
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
    @EnvironmentObject var customDrumPatternManager: CustomDrumPatternManager

    @State private var showAddDrumPatternSheet: Bool = false
    @State private var isHoveringGroup: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("鼓点模式").font(.headline)
                Spacer()

                // Add Pattern to Workspace Button
                Button(action: { showAddDrumPatternSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .help("从库添加鼓点到工作区")
            }
            if appData.performanceConfig.selectedDrumPatterns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("当前没有鼓点模式。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加鼓点模式，或使用快捷键 ⌘1/⌘2... 进行切换")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
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
                                        timeSignature: appData.performanceConfig.timeSignature,
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
                            .contextMenu {
                                Button(role: .destructive) {
                                    appData.removeDrumPattern(patternId: patternId)
                                } label: {
                                    Label("移除鼓点", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringGroup = hovering
            }
        }
        .sheet(isPresented: $showAddDrumPatternSheet) {
            SelectDrumPatternsSheet(initialSelection: appData.performanceConfig.selectedDrumPatterns, onDone: { selectedIDs in
                appData.performanceConfig.selectedDrumPatterns = selectedIDs
                
                // Check if the current active pattern is still valid.
                // If not, set the first available pattern as active.
                let currentActiveId = appData.performanceConfig.activeDrumPatternId
                let isActiveIdValid = currentActiveId != nil && selectedIDs.contains(currentActiveId!)
                
                if !isActiveIdValid {
                    appData.performanceConfig.activeDrumPatternId = selectedIDs.first
                }
                
                showAddDrumPatternSheet = false
            })
            .environmentObject(appData)
            .environmentObject(customDrumPatternManager)
        }
    }

    private func findPatternDetails(for patternId: String) -> (pattern: DrumPattern, category: String)? {
        // Also check custom patterns
        for (_, patterns) in customDrumPatternManager.customDrumPatterns {
            if let pattern = patterns[patternId] {
                return (pattern, "自定义")
            }
        }

        if let library = appData.drumPatternLibrary {
            for (category, patterns) in library {
                if let pattern = patterns[patternId] {
                    return (pattern, category)
                }
            }
        }
        return nil
    }
}

private struct PlayingPatternCardView: View {
    let index: Int
    let pattern: GuitarPattern
    let category: String
    let timeSignature: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlayingPatternView(
                pattern: pattern,
                timeSignature: timeSignature,
                color: isActive ? .accentColor : .primary
            )
            .opacity(isActive ? 1.0 : 0.7)
            .padding(.bottom, 4)
            .padding(.trailing, 35)

            HStack {
                Text(pattern.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
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
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager

    @State private var showAddPlayingPatternSheet: Bool = false
    @State private var isHoveringGroup: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("和弦指法").font(.headline)
                Spacer()

                // Add Pattern to Workspace Button
                Button(action: { showAddPlayingPatternSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .help("从库添加演奏模式到工作区")
            }
            if appData.performanceConfig.selectedPlayingPatterns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("当前没有和弦指法。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加和弦指法，或使用数字键 1/2... 快速选择")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
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
                                        timeSignature: appData.performanceConfig.timeSignature,
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
                            .contextMenu {
                                Button(role: .destructive) {
                                    appData.removePlayingPattern(patternId: patternId)
                                } label: {
                                    Label("移除指法", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringGroup = hovering
            }
        }
        .sheet(isPresented: $showAddPlayingPatternSheet) {
            AddPlayingPatternSheetView()
        }
    }
    
    private func findPlayingPatternDetails(for patternId: String) -> (pattern: GuitarPattern, category: String)? {
        // Search in custom patterns first
        for (_, patterns) in customPlayingPatternManager.customPlayingPatterns {
            if let pattern = patterns.first(where: { $0.id == patternId }) {
                return (pattern, "自定义")
            }
        }
        
        // Then search in system patterns
        if let library = appData.patternLibrary {
            for (category, patterns) in library {
                if let pattern = patterns.first(where: { $0.id == patternId }) {
                    return (pattern, category)
                }
            }
        }
        
        return nil
    }
}

private struct ChordCardView: View {
    @EnvironmentObject var appData: AppData
    let chord: String
    let isFlashing: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Main content - chord name
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

            // Chord diagram in the bottom-left corner
            if let frets = appData.chordLibrary?[chord] {
                ChordDiagramView(frets: frets, color: .primary.opacity(0.8))
                    .frame(width: 40, height: 48)
                    .padding(6)
            }
        }
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
    @State private var isHoveringGroup: Bool = false
    @State private var badgeHoveredForChord: String? = nil
    @State private var showAddAssociationSheet: Bool = false
    @State private var selectedChordForAssociation: String? = nil

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("和弦进行").font(.headline)
                Spacer()
                Button(action: { showAddChordSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .opacity(isHoveringGroup ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
            }
            
            if appData.performanceConfig.chords.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("当前没有和弦进行。")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("点击右上角“+”添加和弦，或在和弦库中选择并添加到进行中。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .frame(height: 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(appData.performanceConfig.chords, id: \.id) { chordConfig in
                        ZStack(alignment: .topTrailing) {
                            ChordCardView(chord: chordConfig.name, isFlashing: flashingChord == chordConfig.name)
                                .animation(.easeInOut(duration: 0.15), value: flashingChord)
                                .onTapGesture {
                                    keyboardHandler.playChordByName(chordConfig.name)
                                }

                            // Shortcut badge (custom or default). Always show a Text badge.
                            let (baseBadgeText, baseBadgeColor): (String, Color) = {
                                // 1) user-assigned shortcut
                                if let shortcutValue = chordConfig.shortcut, let s = Shortcut(stringValue: shortcutValue) {
                                    return (s.displayText, Color.accentColor)
                                }

                                // 2) fallback to sensible default mapping for simple single-letter notes
                                let components = chordConfig.name.split(separator: "_")
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
                            
                            let isBadgeHovered = badgeHoveredForChord == chordConfig.name
                            let badgeText = baseBadgeText
                            let badgeColor = isBadgeHovered ? baseBadgeColor.opacity(0.7) : baseBadgeColor


                            // Badge button: tapping this starts capturing a new shortcut for this chord.
                            Button(action: {
                                captureShortcutForChord(chord: chordConfig.name)
                            }) {
                                Text(badgeText)
                                    .font(.caption2).bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(badgeColor, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation {
                                    badgeHoveredForChord = hovering ? chordConfig.name : nil
                                }
                            }
                            .help("编辑快捷键")
                            .offset(x: -8, y: 8)
                        }
                        // Bottom-right badges for associated playing pattern shortcuts
                        .overlay(alignment: .bottomTrailing) {
                            let shortcuts = sortedPatternShortcuts(for: chordConfig)
                            if !shortcuts.isEmpty {
                                HStack(spacing: 6) {
                                    let maxShow = 3
                                    let shown = Array(shortcuts.prefix(maxShow))
                                    let rest = shortcuts.count > maxShow ? Array(shortcuts.dropFirst(maxShow)) : []
                                    ForEach(shown, id: \.stringValue) { sc in
                                        Text(sc.displayText)
                                            .font(.caption2).bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.15), in: Capsule())
                                    }
                                    if !rest.isEmpty {
                                        Text("+\(rest.count)")
                                            .font(.caption2).bold()
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.gray.opacity(0.12), in: Capsule())
                                            .help(rest.map { $0.displayText }.joined(separator: ", "))
                                    }
                                }
                                .padding(6)
                                .allowsHitTesting(false) // avoid intercepting the tap on the chord card
                            }
                        }
                        .contextMenu {
                            Button {
                                selectedChordForAssociation = chordConfig.name
                                showAddAssociationSheet = true
                            } label: {
                                Label("管理演奏指法关联", systemImage: "link")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                appData.removeChord(chordName: chordConfig.name)
                            } label: {
                                Label("移除和弦", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringGroup = hovering
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
                appData.performanceConfig.chords.append(ChordPerformanceConfig(name: chordName))
            }, existingChordNames: Set(appData.performanceConfig.chords.map { $0.name }))
        }
        .sheet(isPresented: $showAddAssociationSheet) {
            if let chordName = selectedChordForAssociation {
                AddChordPlayingPatternAssociationSheet(chordName: chordName)
            }
        }
    }

    // MARK: - Helpers for sorting pattern association shortcuts
    private func sortedPatternShortcuts(for chordConfig: ChordPerformanceConfig) -> [Shortcut] {
        let shortcuts = chordConfig.patternAssociations.keys.map { $0 }
        return shortcuts.sorted(by: shortcutSortLessThan(_:_:))
    }
    
    private func shortcutSortLessThan(_ a: Shortcut, _ b: Shortcut) -> Bool {
        // Weight modifiers: cmd > ctrl > opt > shift
        func weight(_ s: Shortcut) -> Int {
            var w = 0
            if s.modifiersCommand { w += 8 }
            if s.modifiersControl { w += 4 }
            if s.modifiersOption { w += 2 }
            if s.modifiersShift { w += 1 }
            return w
        }
        let wa = weight(a)
        let wb = weight(b)
        if wa != wb { return wa > wb }
        // Then by key lexicographically
        return a.key < b.key
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