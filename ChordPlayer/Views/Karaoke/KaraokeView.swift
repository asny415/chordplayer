
import SwiftUI
import Combine

// 1. PreferenceKey for measuring the width of the lyric text.
struct LyricWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Use the maximum width found, as views might render multiple times.
        value = max(value, nextValue())
    }
}

// MARK: - Data Models (Unchanged)
struct KaraokeDisplayWord: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let startTime: Double
    let duration: Double
}

struct KaraokeDisplayLine: Identifiable, Hashable {
    let id = UUID()
    let words: [KaraokeDisplayWord]
    let startTime: Double
    let endTime: Double
    
    var lineText: String {
        let joined = words.map { $0.text }.joined()
        if joined.hasSuffix(",") || joined.hasSuffix("，") { return String(joined.dropLast()) }
        return joined
    }
}

// MARK: - Karaoke Line View (Unchanged)
struct KaraokeLineView: View {
    let line: KaraokeDisplayLine
    let playbackTime: Double
    
    private let highlightColor = Color(red: 0, green: 1, blue: 0.9)

    var body: some View {
        let baseFont = Font.system(.largeTitle, design: .monospaced).weight(.bold)
        
        ZStack(alignment: .leading) {
            Text(line.lineText)
                .font(baseFont)
                .foregroundStyle(.secondary)

            Text(line.lineText)
                .font(baseFont)
                .foregroundStyle(highlightColor)
                .shadow(color: highlightColor.opacity(0.6), radius: 8, x: 0, y: 0)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: calculateMaskWidth())
                }
                .animation(.linear(duration: 0.05), value: playbackTime)
        }
        .frame(height: 60)
    }

    private func calculateMaskWidth() -> CGFloat {
        guard let firstWord = line.words.first else { return 0 }
        let fullWidth = estimateWidth(for: line.lineText)
        
        if playbackTime < firstWord.startTime { return 0 }
        if playbackTime >= line.endTime { return fullWidth }

        var accumulatedWidth: CGFloat = 0
        for word in line.words {
            if playbackTime >= word.startTime + word.duration {
                accumulatedWidth += estimateWidth(for: word.text)
            } else if playbackTime >= word.startTime && playbackTime < word.startTime + word.duration {
                if word.duration > 0 {
                    let progress = (playbackTime - word.startTime) / word.duration
                    accumulatedWidth += estimateWidth(for: word.text) * CGFloat(progress)
                }
                break
            }
        }
        return accumulatedWidth
    }

    private func estimateWidth(for text: String) -> CGFloat {
        let charWidth: CGFloat = 28.8
        return CGFloat(text.count) * charWidth
    }
}

// MARK: - Main Karaoke View (FINAL IMPLEMENTATION with PreferenceKey)
struct KaraokeView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var songPlayer: PresetArrangerPlayer
    
    @State private var allDisplayLines: [KaraokeDisplayLine] = []
    
    @State private var currentLine: KaraokeDisplayLine?
    @State private var nextLine: KaraokeDisplayLine?
    @State private var countdown: Int = 0
    
    // 2. State variable to hold the measured width of the active lyric line.
    @State private var activeLineWidth: CGFloat = 0
    
    private let highlightColor = Color(red: 0, green: 1, blue: 0.9)
    private let countdownViewWidth: CGFloat = 100

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                // This parent VStack with two Spacers handles the overall vertical centering.
                VStack {
                    Spacer()

                    // This parent HStack with two Spacers handles the overall horizontal centering.
                    HStack {
                        Spacer()

                        // This VStack contains both the content and the proportional spacer below it.
                        // Centering this entire VStack achieves the "slightly above center" effect.
                        VStack(spacing: 0) {
                            // The "Sandwich" layout block for lyrics and countdown.
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                
                                // --- LEFT: THE COUNTDOWN ---
                                Text(String(repeating: "•", count: countdown))
                                    .font(.system(.title3, design: .monospaced).weight(.bold))
                                    .foregroundStyle(highlightColor)
                                    .frame(width: 100, alignment: .trailing)
                                    .lineLimit(1)
                                    .opacity(countdown > 0 ? 1 : 0)

                                // --- MIDDLE: THE LYRICS ---
                                VStack(alignment: .leading, spacing: 20) {
                                    if let line = currentLine {
                                        KaraokeLineView(line: line, playbackTime: songPlayer.playbackPosition)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Rectangle().fill(Color.clear).frame(height: 60)
                                    }
                                    
                                    if let line = nextLine {
                                        Text(line.lineText)
                                            .font(.system(.title2, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Rectangle().fill(Color.clear).frame(height: 40)
                                    }
                                }

                                // --- RIGHT: THE DUMMY BALANCER ---
                                Text(" ")
                                    .frame(width: 100)
                            }

                            // The user-designed proportional spacer for responsive vertical positioning.
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: geometry.size.height / 5)
                        }
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
            .onAppear(perform: setupAndProcessLyrics)
            .onReceive(songPlayer.$playbackPosition) { time in
                withAnimation(.linear(duration: 0.05)) {
                    updateVisibleLines(at: time)
                }
            }
            
            if let presetName = appData.preset?.name {
                Text(presetName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }
    
    // 6. Function to calculate the precise X coordinate for the countdown.
    private func calculateCountdownX(screenWidth: CGFloat) -> CGFloat {
        let screenCenterX = screenWidth / 2
        let lyricStartX = screenCenterX - (activeLineWidth / 2)
        let countdownCenterX = lyricStartX - (countdownViewWidth / 2) - 16 // 16 is for spacing
        return countdownCenterX
    }
    
    private func updateVisibleLines(at time: Double) {
        var newCountdown = 0
        if let nextLineIndex = allDisplayLines.firstIndex(where: { $0.startTime > time }) {
            let nextLine = allDisplayLines[nextLineIndex]
            let prevLineIndex = nextLineIndex - 1
            var isSegmentStart = false

            if prevLineIndex >= 0 {
                if (nextLine.startTime - allDisplayLines[prevLineIndex].endTime) > 10.0 {
                    isSegmentStart = true
                }
            } else {
                isSegmentStart = true
            }

            if isSegmentStart {
                let timeToStart = nextLine.startTime - time
                if timeToStart > 2 && timeToStart <= 3 {
                    newCountdown = 3
                } else if timeToStart > 1 && timeToStart <= 2 {
                    newCountdown = 2
                } else if timeToStart > 0 && timeToStart <= 1 {
                    newCountdown = 1
                }
            }
        }
        if self.countdown != newCountdown {
            self.countdown = newCountdown
        }

        var currentDisplayIndex: Int?
        if let activeIndex = allDisplayLines.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            currentDisplayIndex = activeIndex
        } else {
            if let nextLineIndex = allDisplayLines.firstIndex(where: { $0.startTime > time }) {
                let prevLineIndex = nextLineIndex - 1
                if prevLineIndex >= 0 {
                    let prevLine = allDisplayLines[prevLineIndex]
                    let nextLine = allDisplayLines[nextLineIndex]
                    let gapDuration = nextLine.startTime - prevLine.endTime

                    if gapDuration > 10.0 {
                        if time >= nextLine.startTime - 5.0 {
                            currentDisplayIndex = nextLineIndex
                        } else {
                            currentDisplayIndex = nil
                        }
                    } else {
                        currentDisplayIndex = nextLineIndex
                    }
                } else {
                    let firstLine = allDisplayLines[nextLineIndex]
                    if time >= firstLine.startTime - 5.0 {
                        currentDisplayIndex = nextLineIndex
                    } else {
                        currentDisplayIndex = nil
                    }
                }
            } else {
                currentDisplayIndex = nil
            }
        }

        let newCurrentLine = currentDisplayIndex.flatMap { allDisplayLines.indices.contains($0) ? allDisplayLines[$0] : nil }
        var newNextLine: KaraokeDisplayLine? = nil

        if let currentIndex = currentDisplayIndex {
            let nextPotentialIndex = currentIndex + 1
            if allDisplayLines.indices.contains(nextPotentialIndex) {
                let currentLine = allDisplayLines[currentIndex]
                let nextPotentialLine = allDisplayLines[nextPotentialIndex]
                let gapToNext = nextPotentialLine.startTime - currentLine.endTime
                if gapToNext <= 10.0 {
                    newNextLine = nextPotentialLine
                }
            }
        }

        if newCurrentLine?.id != self.currentLine?.id || newNextLine?.id != self.nextLine?.id {
            self.currentLine = newCurrentLine
            self.nextLine = newNextLine
        }
    }
    
    private func setupAndProcessLyrics() {
        guard let preset = appData.preset else { self.allDisplayLines = []; return }
        let ticksPerBeat = 12.0
        var allWords: [KaraokeDisplayWord] = []
        let allLyricSegments = preset.arrangement.lyricsTracks.flatMap { $0.lyrics }.sorted { $0.startBeat < $1.startBeat }
        for arrangedSegment in allLyricSegments {
            var melodicData: MelodicLyricSegment?
            if let melodicId = arrangedSegment.melodicLyricSegmentId { melodicData = preset.melodicLyricSegments.first { $0.id == melodicId } }
            else { melodicData = preset.melodicLyricSegments.first { $0.id == arrangedSegment.id } }
            guard let foundMelodicData = melodicData else { continue }
            let segmentStartBeat = arrangedSegment.startBeat
            let sortedItems = foundMelodicData.items.sorted { $0.positionInTicks < $1.positionInTicks }
            for (index, item) in sortedItems.enumerated() {
                if item.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let startTime = segmentStartBeat + (Double(item.positionInTicks) / ticksPerBeat)
                var currentEndTime = startTime + (Double(item.durationInTicks ?? 3) / ticksPerBeat) // Default to 16th note duration
                for j in (index + 1)..<sortedItems.count {
                    let nextItem = sortedItems[j]
                    let nextItemStartTime = segmentStartBeat + (Double(nextItem.positionInTicks) / ticksPerBeat)
                    if nextItemStartTime > currentEndTime { break }
                    if !nextItem.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                    currentEndTime = nextItemStartTime + (Double(nextItem.durationInTicks ?? 3) / ticksPerBeat)
                }
                let duration = currentEndTime - startTime
                let finalDuration = max(duration, 3.0 / ticksPerBeat) // Min duration of a 16th note
                allWords.append(KaraokeDisplayWord(text: item.word, startTime: startTime, duration: finalDuration))
            }
        }
        var newDisplayLines: [KaraokeDisplayLine] = []
        var currentLineWords: [KaraokeDisplayWord] = []
        for word in allWords {
            currentLineWords.append(word)
            if word.text.contains(",") || word.text.contains("，") {
                if !currentLineWords.isEmpty {
                    let lineStartTime = currentLineWords.first!.startTime
                    let lineEndTime = currentLineWords.last!.startTime + currentLineWords.last!.duration
                    newDisplayLines.append(KaraokeDisplayLine(words: currentLineWords, startTime: lineStartTime, endTime: lineEndTime))
                    currentLineWords = []
                }
            }
        }
        if !currentLineWords.isEmpty {
            let lineStartTime = currentLineWords.first!.startTime
            let lineEndTime = currentLineWords.last!.startTime + currentLineWords.last!.duration
            newDisplayLines.append(KaraokeDisplayLine(words: currentLineWords, startTime: lineStartTime, endTime: lineEndTime))
        }
        self.allDisplayLines = newDisplayLines
        updateVisibleLines(at: 0)
    }
}

// MARK: - Helper (Unchanged)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
