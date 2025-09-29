
import SwiftUI
import Combine

// MARK: - Karaoke Display Models
/// A struct representing a single word in a lyric line for display purposes.
struct KaraokeDisplayWord: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let startTime: Double // in beats
    let duration: Double // in beats
}

/// A struct representing a single line of lyrics, composed of multiple words.
struct KaraokeDisplayLine: Identifiable, Hashable {
    let id = UUID()
    let words: [KaraokeDisplayWord]
    let startTime: Double // in beats
    let endTime: Double // in beats
    
    var lineText: String {
        let joined = words.map { $0.text }.joined()
        if joined.hasSuffix(",") {
            return String(joined.dropLast())
        }
        return joined
    }
}

// MARK: - Karaoke Line View
/// A view that displays a single line of lyrics with a real-time "wipe" animation.
struct KaraokeLineView: View {
    let line: KaraokeDisplayLine
    let playbackTime: Double
    let isActive: Bool
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Background text (inactive color) - using monospaced font for consistent width
                Text(line.lineText)
                    .font(.system(isActive ? .largeTitle : .title2, design: .monospaced).weight(.bold))
                    .foregroundColor(isActive ? .white.opacity(0.4) : .white.opacity(0.6))
                
                // Foreground text (active color, clipped) - using monospaced font
                Text(line.lineText)
                    .font(.system(isActive ? .largeTitle : .title2, design: .monospaced).weight(.bold))
                    .foregroundColor(isActive ? Color(hex: "#FFFF00") : .white.opacity(0.6))
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: calculateMaskWidth(fullWidth: proxy.size.width), height: 60)
                    }
                    .animation(.linear(duration: 0.05), value: playbackTime)
            }
        }
        .frame(height: isActive ? 60 : 40) // Adjust frame height based on active state
    }
    
    private func calculateMaskWidth(fullWidth: CGFloat) -> CGFloat {
        var accumulatedWidth: CGFloat = 0

        for word in line.words {
            let wordStart = word.startTime
            let wordEnd = word.startTime + word.duration

            if playbackTime < wordStart {
                // We haven't reached this word yet, so the final width is what we've accumulated so far.
                return accumulatedWidth
            }

            if playbackTime >= wordEnd {
                // We are past this word, so add its full width and continue to the next.
                accumulatedWidth += width(of: word.text)
            } else {
                // We are currently within this word's duration.
                if word.duration > 0 {
                    let progress = (playbackTime - wordStart) / word.duration
                    accumulatedWidth += width(of: word.text) * CGFloat(progress)
                }
                // Since we're in the current word, we don't need to process any more words.
                return accumulatedWidth
            }
        }

        // If the loop completes, it means playbackTime is past all words.
        return fullWidth
    }
    
    private func width(of text: String) -> CGFloat {
        // Using a more tuned estimation for monospaced fonts.
        let charWidth: CGFloat = isActive ? 28.8 : 19.2 // largeTitle ~28.8pt, title2 ~19.2pt
        return CGFloat(text.count) * charWidth
    }
}

// MARK: - Main Karaoke View
struct KaraokeView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var songPlayer: PresetArrangerPlayer
    
    @State private var displayLines: [KaraokeDisplayLine] = []
    @State private var currentLineIndex: Int? = nil
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#1a2a6c"), Color(hex: "#000033"), Color(hex: "#1a2a6c")]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Lyrics
            VStack(spacing: 20) {
                if let currentIndex = currentLineIndex, displayLines.indices.contains(currentIndex) {
                    // Previous Line (if exists)
                    if currentIndex > 0 {
                        Text(displayLines[currentIndex - 1].lineText)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.horizontal)
                    } else {
                        Spacer().frame(height: 30)
                    }
                    
                    // Active Line
                    KaraokeLineView(line: displayLines[currentIndex], playbackTime: songPlayer.playbackPosition, isActive: true)
                    
                    // Next Line (if exists)
                    if displayLines.indices.contains(currentIndex + 1) {
                        Text(displayLines[currentIndex + 1].lineText)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal)
                    } else {
                        Spacer().frame(height: 40)
                    }
                    
                } else {
                    Text("...")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(.top, 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: setupAndProcessLyrics)
        .onReceive(songPlayer.$playbackPosition) { time in
            updateCurrentLine(at: time)
        }
    }
    
    private func setupAndProcessLyrics() {
        guard let preset = appData.preset else {
            self.displayLines = []
            return
        }
        
        // MARK: Pass 1: Collect all words with absolute timing
        let sixteenthNoteDurationInBeats = 0.25
        var allWords: [KaraokeDisplayWord] = []
        let allLyricSegments = preset.arrangement.lyricsTracks.flatMap { $0.lyrics }.sorted { $0.startBeat < $1.startBeat }

        for arrangedSegment in allLyricSegments {
            var melodicData: MelodicLyricSegment?
            if let melodicId = arrangedSegment.melodicLyricSegmentId {
                melodicData = preset.melodicLyricSegments.first { $0.id == melodicId }
            } else {
                melodicData = preset.melodicLyricSegments.first { $0.id == arrangedSegment.id }
            }

            guard let foundMelodicData = melodicData else { continue }
            
            let segmentStartBeat = arrangedSegment.startBeat
            let sortedItems = foundMelodicData.items.sorted { $0.position < $1.position }
            
            for (index, item) in sortedItems.enumerated() {
                // Skip items that are just placeholders without words.
                if item.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                
                let startTime = segmentStartBeat + (Double(item.position) * sixteenthNoteDurationInBeats)
                
                // Final Duration Logic: Extends over contiguous notes, stops at gaps or new words.
                var currentEndTime = startTime + (Double(item.duration ?? 1) * sixteenthNoteDurationInBeats)

                // Look ahead to find the true end time
                for j in (index + 1)..<sortedItems.count {
                    let nextItem = sortedItems[j]
                    let nextItemStartTime = segmentStartBeat + (Double(nextItem.position) * sixteenthNoteDurationInBeats)

                    // If there's a gap between the current end time and the next note's start, stop extending.
                    if nextItemStartTime > currentEndTime {
                        break
                    }

                    // If the next note starts a new word, stop extending.
                    if !nextItem.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        break
                    }

                    // Otherwise, this is a contiguous note without a word. Absorb its duration and continue.
                    currentEndTime = nextItemStartTime + (Double(nextItem.duration ?? 1) * sixteenthNoteDurationInBeats)
                }

                let duration = currentEndTime - startTime
                let finalDuration = max(duration, sixteenthNoteDurationInBeats)
                
                allWords.append(KaraokeDisplayWord(text: item.word, startTime: startTime, duration: finalDuration))
            }
        }

        // MARK: Pass 2: Group words into lines based on comma delimiter
        var newDisplayLines: [KaraokeDisplayLine] = []
        var currentLineWords: [KaraokeDisplayWord] = []
        for word in allWords {
            currentLineWords.append(word)
            if word.text.contains(",") {
                if !currentLineWords.isEmpty {
                    let lineStartTime = currentLineWords.first!.startTime
                    let lineEndTime = currentLineWords.last!.startTime + currentLineWords.last!.duration
                    newDisplayLines.append(KaraokeDisplayLine(words: currentLineWords, startTime: lineStartTime, endTime: lineEndTime))
                    currentLineWords = [] // Start a new line
                }
            }
        }
        // Add the last line if it doesn't end with a comma
        if !currentLineWords.isEmpty {
            let lineStartTime = currentLineWords.first!.startTime
            let lineEndTime = currentLineWords.last!.startTime + currentLineWords.last!.duration
            newDisplayLines.append(KaraokeDisplayLine(words: currentLineWords, startTime: lineStartTime, endTime: lineEndTime))
        }
        
        self.displayLines = newDisplayLines
        
        // DEBUG: Print processed lyrics to console
        print("--- Karaoke Lyrics Processed (With Line Breaks) ---")
        if self.displayLines.isEmpty {
            print("No lyrics were found in the arrangement.")
        } else {
            for line in self.displayLines {
                print("[Line \(String(format: "%.2f", line.startTime))b - \(String(format: "%.2f", line.endTime))b]: \(line.lineText)")
            }
        }
        print("---------------------------------------------------")

        updateCurrentLine(at: 0)
    }
    
    private func updateCurrentLine(at time: Double) {
        // Find the index of the line that should be currently active
        if let index = displayLines.firstIndex(where: { time >= $0.startTime && time < $0.endTime }) {
            if index != currentLineIndex {
                currentLineIndex = index
            }
        } else if time >= (displayLines.last?.endTime ?? 0) {
            // After the last line
            currentLineIndex = displayLines.count - 1
        } else if time < (displayLines.first?.startTime ?? 0) {
            // Before the first line
            currentLineIndex = 0
        }
    }
}

// MARK: - Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
