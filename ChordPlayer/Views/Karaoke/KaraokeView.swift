import SwiftUI
import Combine

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
        // Clean up trailing commas often found in lyric data
        if joined.hasSuffix(",") { return String(joined.dropLast()) }
        return joined
    }
}

// MARK: - Karaoke Line View (Unchanged)
// This view is responsible for the word-by-word highlighting and doesn't need changes.
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
        let charWidth: CGFloat = 28.8 // .largeTitle monospaced estimation
        return CGFloat(text.count) * charWidth
    }
}

// MARK: - Main Karaoke View (NEW IMPLEMENTATION)
struct KaraokeView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var songPlayer: PresetArrangerPlayer
    
    // Processed lyric data
    @State private var allDisplayLines: [KaraokeDisplayLine] = []
    
    // State for the new "rolling" display logic
    @State private var currentLine: KaraokeDisplayLine?
    @State private var nextLine: KaraokeDisplayLine?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                // 1. Current Line (Top, Left-aligned)
                // This is the line currently being sung.
                if let line = currentLine {
                    KaraokeLineView(line: line, playbackTime: songPlayer.playbackPosition)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Placeholder to maintain layout
                    Rectangle().fill(Color.clear).frame(height: 60)
                }

                // 2. Next Line (Bottom, Right-aligned)
                // This is the upcoming line, shown for preparation.
                if let line = nextLine {
                    Text(line.lineText)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    // Placeholder to maintain layout
                    Rectangle().fill(Color.clear).frame(height: 40)
                }
                
                Spacer()
            }
            .frame(width: geometry.size.width * 2 / 3) // Fixed width as requested
            .frame(maxWidth: .infinity) // Center the VStack horizontally
            .padding(.top, 50)
        }
        .onAppear(perform: setupAndProcessLyrics)
        .onReceive(songPlayer.$playbackPosition) { time in
            // No animation wrapper here for instant updates
            updateVisibleLines(at: time)
        }
    }
    
    private func updateVisibleLines(at time: Double) {
        var currentDisplayIndex: Int?

        // Find the line that is currently singing, if any.
        if let activeIndex = allDisplayLines.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            currentDisplayIndex = activeIndex
        } else {
            // We are in a gap. Find the next line to decide what to do.
            if let nextLineIndex = allDisplayLines.firstIndex(where: { $0.startTime > time }) {
                let prevLineIndex = nextLineIndex - 1

                if prevLineIndex >= 0 {
                    // --- GAP BETWEEN TWO LINES ---
                    let prevLine = allDisplayLines[prevLineIndex]
                    let nextLine = allDisplayLines[nextLineIndex]
                    let gapDuration = nextLine.startTime - prevLine.endTime

                    if gapDuration > 10.0 {
                        // LONG GAP: Blank screen, then 5s pre-roll.
                        if time >= nextLine.startTime - 5.0 {
                            currentDisplayIndex = nextLineIndex // Pre-roll window
                        } else {
                            currentDisplayIndex = nil // Blank screen during gap
                        }
                    } else {
                        // SHORT GAP: Switch immediately after the previous line ends.
                        currentDisplayIndex = nextLineIndex
                    }
                } else {
                    // --- GAP BEFORE THE VERY FIRST LINE ---
                    // Treat as a long gap: blank, then 5s pre-roll.
                    let firstLine = allDisplayLines[nextLineIndex]
                    if time >= firstLine.startTime - 5.0 {
                        currentDisplayIndex = nextLineIndex
                    } else {
                        currentDisplayIndex = nil
                    }
                }
            } else {
                // --- AFTER THE LAST LINE HAS FINISHED ---
                // The song is over, show a blank screen.
                currentDisplayIndex = nil
            }
        }

        // --- SET THE STATE BASED ON THE NEW LOGIC ---
        let newCurrentLine = currentDisplayIndex.flatMap { allDisplayLines.indices.contains($0) ? allDisplayLines[$0] : nil }
        var newNextLine: KaraokeDisplayLine? = nil // Default to nil

        // Determine if a "next line" should be shown.
        if let currentIndex = currentDisplayIndex {
            let nextPotentialIndex = currentIndex + 1
            if allDisplayLines.indices.contains(nextPotentialIndex) {
                let currentLine = allDisplayLines[currentIndex]
                let nextPotentialLine = allDisplayLines[nextPotentialIndex]
                
                let gapToNext = nextPotentialLine.startTime - currentLine.endTime

                // Only show the next line if it's part of the same segment (short gap).
                if gapToNext <= 10.0 {
                    newNextLine = nextPotentialLine
                }
            }
        }

        // Update state only if there's a change to avoid unnecessary view re-renders.
        if newCurrentLine?.id != self.currentLine?.id || newNextLine?.id != self.nextLine?.id {
            self.currentLine = newCurrentLine
            self.nextLine = newNextLine
        }
    }
    
    // This function remains the same for parsing the raw data.
    private func setupAndProcessLyrics() {
        guard let preset = appData.preset else { self.allDisplayLines = []; return }
        let sixteenthNoteDurationInBeats = 0.25
        var allWords: [KaraokeDisplayWord] = []
        let allLyricSegments = preset.arrangement.lyricsTracks.flatMap { $0.lyrics }.sorted { $0.startBeat < $1.startBeat }
        for arrangedSegment in allLyricSegments {
            var melodicData: MelodicLyricSegment?
            if let melodicId = arrangedSegment.melodicLyricSegmentId { melodicData = preset.melodicLyricSegments.first { $0.id == melodicId } }
            else { melodicData = preset.melodicLyricSegments.first { $0.id == arrangedSegment.id } }
            guard let foundMelodicData = melodicData else { continue }
            let segmentStartBeat = arrangedSegment.startBeat
            let sortedItems = foundMelodicData.items.sorted { $0.position < $1.position }
            for (index, item) in sortedItems.enumerated() {
                if item.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let startTime = segmentStartBeat + (Double(item.position) * sixteenthNoteDurationInBeats)
                var currentEndTime = startTime + (Double(item.duration ?? 1) * sixteenthNoteDurationInBeats)
                for j in (index + 1)..<sortedItems.count {
                    let nextItem = sortedItems[j]
                    let nextItemStartTime = segmentStartBeat + (Double(nextItem.position) * sixteenthNoteDurationInBeats)
                    if nextItemStartTime > currentEndTime { break }
                    if !nextItem.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                    currentEndTime = nextItemStartTime + (Double(nextItem.duration ?? 1) * sixteenthNoteDurationInBeats)
                }
                let duration = currentEndTime - startTime
                let finalDuration = max(duration, sixteenthNoteDurationInBeats)
                allWords.append(KaraokeDisplayWord(text: item.word, startTime: startTime, duration: finalDuration))
            }
        }
        var newDisplayLines: [KaraokeDisplayLine] = []
        var currentLineWords: [KaraokeDisplayWord] = []
        for word in allWords {
            currentLineWords.append(word)
            if word.text.contains(",") {
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
        // Set initial state
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