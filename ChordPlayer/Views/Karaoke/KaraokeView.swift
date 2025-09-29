
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
        if joined.hasSuffix(",") { return String(joined.dropLast()) }
        return joined
    }
}

// MARK: - Karaoke Line View (Refactored for Simplicity)
struct KaraokeLineView: View {
    let line: KaraokeDisplayLine
    let playbackTime: Double
    
    // A vibrant, eye-catching highlight color
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
        // Estimation for a monospaced font. A more robust solution would use AppKit/UIKit text measurement.
        let charWidth: CGFloat = 28.8 // .largeTitle monospaced estimation
        return CGFloat(text.count) * charWidth
    }
}

// MARK: - Main Karaoke View (Complete Refactor)
struct KaraokeView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var songPlayer: PresetArrangerPlayer
    
    @State private var displayLines: [KaraokeDisplayLine] = []
    
    // State for the new, simplified architecture
    @State private var activeLineIndex: Int? = nil
    @State private var showPreRollDots: Bool = false

    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
            
            VStack(spacing: 20) {
                // 1. Active Line Slot
                ZStack {
                    if showPreRollDots {
                        Text("...")
                            .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let index = activeLineIndex, displayLines.indices.contains(index) {
                        KaraokeLineView(line: displayLines[index], playbackTime: songPlayer.playbackPosition)
                            .id("active_\(index)")
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                    }
                }
                .frame(height: 60)
                
                // 2. Next Line Slot
                ZStack {
                    if let nextLine = getNextLine() {
                        Text(nextLine.lineText)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(.secondary)
                            .id("next_\(nextLine.id)")
                            .transition(.opacity)
                    }
                }
                .frame(height: 40)
                
                Spacer()
            }
            .padding(.top, 50)
        }
        .onAppear(perform: setupAndProcessLyrics)
        .onReceive(songPlayer.$playbackPosition) { time in
            updateState(at: time)
        }
    }
    
    private func getNextLine() -> KaraokeDisplayLine? {
        guard let currentIndex = activeLineIndex, displayLines.indices.contains(currentIndex + 1) else {
            return nil
        }
        
        let currentLine = displayLines[currentIndex]
        let nextLine = displayLines[currentIndex + 1]
        
        // Per rule #1: Only show next line if the gap is less than 10 seconds (40 beats @ 240bpm, a safe high number)
        let beatsIn10Seconds = 10.0 * (appData.preset?.bpm ?? 120) / 60.0
        if (nextLine.startTime - currentLine.endTime) > beatsIn10Seconds {
            return nil
        }
        
        return nextLine
    }

    private func updateState(at time: Double) {
        let beatsIn10Seconds = 10.0 * (appData.preset?.bpm ?? 120) / 60.0
        let COUNTDOWN_THRESHOLD: Double = 4.0

        // Determine the new active index
        let newActiveIndex = displayLines.firstIndex { time >= $0.startTime && time < $0.endTime }
        
        if newActiveIndex != activeLineIndex {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                activeLineIndex = newActiveIndex
            }
        }
        
        // Determine if pre-roll dots or countdown should be shown
        var shouldShowDots = false
        if newActiveIndex == nil { // We are in a gap
            // Find the next line to determine if it's a segment start
            let nextLineIndex = displayLines.firstIndex { $0.startTime > time }
            if let nextIndex = nextLineIndex, displayLines.indices.contains(nextIndex) {
                let nextLine = displayLines[nextIndex]
                let prevLineIndex = nextIndex - 1
                
                let gap: Double
                if prevLineIndex >= 0 {
                    gap = nextLine.startTime - displayLines[prevLineIndex].endTime
                } else {
                    gap = nextLine.startTime // Gap before the first line
                }
                
                if gap > beatsIn10Seconds {
                    let beatsToNextLine = nextLine.startTime - time
                    if beatsToNextLine <= COUNTDOWN_THRESHOLD && beatsToNextLine > 0 {
                        shouldShowDots = true
                    }
                }
            }
        }
        
        if showPreRollDots != shouldShowDots {
            withAnimation(.easeInOut) {
                showPreRollDots = shouldShowDots
            }
        }
    }
    
    // This function remains the same as the last correct version
    private func setupAndProcessLyrics() {
        guard let preset = appData.preset else { self.displayLines = []; return }
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
        self.displayLines = newDisplayLines
        updateState(at: 0)
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
