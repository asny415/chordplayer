
import SwiftUI

struct TimingDisplayView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    private var beatsPerMeasure: Int {
        let timeSigParts = appData.performanceConfig.timeSignature.split(separator: "/")
        return Int(timeSigParts.first.map(String.init) ?? "4") ?? 4
    }
    
    private var currentTotalBeat: Int {
        let measure = appData.currentMeasure
        let beat = appData.effectiveCurrentBeat
        
        if measure == 0 {
            return beat
        } else {
            return (measure - 1) * beatsPerMeasure + beat
        }
    }
    
    private func getUpcomingLyrics() -> [Lyric] {
        let allLyrics = appData.performanceConfig.lyrics.sorted { $0.timeRanges.first?.startBeat ?? 0 < $1.timeRanges.first?.startBeat ?? 0 }
        let previewBeat = currentTotalBeat + 2 // Start previewing 2 beats ahead

        // Find the primary lyric: the one that is currently active or the next one to be active.
        guard let primaryLyricIndex = allLyrics.firstIndex(where: { lyric in
            lyric.timeRanges.contains { $0.endBeat >= previewBeat }
        }) else {
            return [] // No more lyrics
        }
        
        let primaryLyric = allLyrics[primaryLyricIndex]
        var results = [primaryLyric]
        
        // Check if the primary lyric should be on the first line or second
        let isPrimaryLyricImminent = primaryLyric.timeRanges.contains { $0.startBeat <= previewBeat }
        
        var lastLyric = primaryLyric
        var currentIndex = primaryLyricIndex
        
        // If the primary lyric is not imminent, it means it's the second line.
        // We should try to find one more to be the third line.
        let maxLyrics = isPrimaryLyricImminent ? 3 : 2

        while results.count < maxLyrics {
            if currentIndex + 1 < allLyrics.count {
                let nextLyric = allLyrics[currentIndex + 1]
                if (nextLyric.timeRanges.first?.startBeat ?? 0) - (lastLyric.timeRanges.first?.endBeat ?? 0) < beatsPerMeasure {
                    results.append(nextLyric)
                    lastLyric = nextLyric
                    currentIndex += 1
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        // If the primary lyric is not imminent, it should be on the second line.
        // We prepend a placeholder to push it down.
        if !isPrimaryLyricImminent {
            results.insert(Lyric(content: "", timeRanges: []), at: 0)
        }

        return Array(results.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Beat timeline
            HStack(spacing: 0) {
                let indices = Array(0..<6)
                ForEach(indices, id: \.self) { index in
                    TimingBeatView(
                        index: index,
                        appData: appData,
                        keyboardHandler: keyboardHandler,
                        calculateBeatForIndex: { currentTotalBeat - 1 + $0 },
                        getContentForBeat: getContentForBeat,
                        getChordNameForBeat: getChordNameForBeat
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // Lyrics display
            VStack(spacing: 10) {
                let upcomingLyrics = getUpcomingLyrics()
                ForEach(upcomingLyrics.indices, id: \.self) { index in
                    let lyric = upcomingLyrics[index]
                    Text(lyric.content)
                        .font(fontForLyric(at: index, isPlaceholder: lyric.content.isEmpty))
                        .foregroundColor(colorForLyric(at: index))
                        .fontWeight(fontWeightForLyric(at: index))
                        .multilineTextAlignment(.center)
                        .id(lyric.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.easeInOut, value: getUpcomingLyrics().map { $0.id })

            // Bottom measure counter
            if appData.totalMeasures > 0 {
                Text("\(appData.currentMeasure) / \(appData.totalMeasures)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .background(Material.thin, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func fontForLyric(at index: Int, isPlaceholder: Bool) -> Font {
        if isPlaceholder { return .largeTitle } // Keep space
        switch index {
        case 0: return .largeTitle
        case 1: return .title2
        default: return .title3
        }
    }
    
    private func colorForLyric(at index: Int) -> Color {
        switch index {
        case 0: return .primary
        case 1: return .secondary
        default: return Color(NSColor.tertiaryLabelColor)
        }
    }
    
    private func fontWeightForLyric(at index: Int) -> Font.Weight {
        switch index {
        case 0: return .bold
        case 1: return .medium
        default: return .regular
        }
    }
    
    private func getContentForBeat(_ beat: Int) -> String {
        if let event = appData.autoPlaySchedule.first(where: { $0.triggerBeat == beat }) {
            if let shortcutValue = event.shortcut, let shortcut = Shortcut(stringValue: shortcutValue) {
                return shortcut.displayText
            } else {
                return getDefaultShortcutForChord(event.chordName) ?? "?"
            }
        }
        return "·"
    }
    
    private func getChordNameForBeat(_ beat: Int) -> String? {
        if let event = appData.autoPlaySchedule.first(where: { $0.triggerBeat == beat }) {
            return event.chordName
        }
        return nil
    }
    
    private func getDefaultShortcutForChord(_ chordName: String) -> String? {
        let components = chordName.split(separator: "_")
        guard components.count >= 2 else { return nil }
        
        let quality = String(components.last!)
        let noteParts = components.dropLast()
        let noteRaw = noteParts.joined(separator: "_")
        let noteDisplay = noteRaw.replacingOccurrences(of: "_Sharp", with: "#")
        
        if noteDisplay.count == 1 {
            if quality == "Major" {
                return noteDisplay.uppercased()
            } else if quality == "Minor" {
                return "⇧\(noteDisplay.uppercased())"
            }
        }
        return nil
    }
}

struct TimingBeatView: View {
    let index: Int
    @ObservedObject var appData: AppData
    @ObservedObject var keyboardHandler: KeyboardHandler
    let calculateBeatForIndex: (Int) -> Int
    let getContentForBeat: (Int) -> String
    let getChordNameForBeat: (Int) -> String?
    
    var body: some View {
        let beatForIndex = calculateBeatForIndex(index)
        let content = getContentForBeat(beatForIndex)
        let isCurrentBeat = index == 2
        
        let shouldHighlight: Bool = {
            if appData.playingMode == .assisted {
                return isCurrentBeat && content != "·" && appData.currentActivePositionTriggered
            } else if appData.playingMode == .automatic {
                return isCurrentBeat && content != "·"
            }
            return false
        }()
        
        BeatLabel(
            beat: beatForIndex,
            isCurrentBeat: isCurrentBeat,
            content: content,
            shouldHighlightForAction: shouldHighlight
        )
    }
}

struct BeatLabel: View {
    let beat: Int
    let isCurrentBeat: Bool
    let content: String
    let shouldHighlightForAction: Bool
    
    init(beat: Int, isCurrentBeat: Bool, content: String, shouldHighlightForAction: Bool = false) {
        self.beat = beat
        self.isCurrentBeat = isCurrentBeat
        self.content = content
        self.shouldHighlightForAction = shouldHighlightForAction
    }
    
    var body: some View {
        Text(content)
            .font(.system(.title3, weight: shouldHighlightForAction ? .bold : .semibold))
            .foregroundColor(shouldHighlightForAction ? .white : (isCurrentBeat ? .primary : (content == "·" ? .secondary : .primary)))
            .frame(width: 60, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(shouldHighlightForAction ? Color.orange : (isCurrentBeat ? Color.accentColor.opacity(0.3) : Color.clear))
            )
            .background(Material.thin, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(shouldHighlightForAction ? Color.orange : (isCurrentBeat ? Color.accentColor : Color.clear), lineWidth: shouldHighlightForAction ? 3 : 2)
            )
    }
}
