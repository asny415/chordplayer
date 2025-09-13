
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
            // 预备拍阶段：effectiveCurrentBeat已经是负数(-4, -3, -2, -1)
            return beat
        } else {
            // 正式演奏阶段：使用原公式
            return (measure - 1) * beatsPerMeasure + beat
        }
    }
    
    private func calculateBeatForIndex(_ index: Int) -> Int {
        return currentTotalBeat - 1 + index
    }
    
    private func getContentForBeat(_ beat: Int) -> String {
        // 从autoPlaySchedule中查找指定beat的事件
        // 第一个和弦通常在triggerBeat=0时出现
        if let event = appData.autoPlaySchedule.first(where: { $0.triggerBeat == beat }) {
            if let shortcutValue = event.shortcut, let shortcut = Shortcut(stringValue: shortcutValue) {
                return shortcut.displayText
            } else {
                return getDefaultShortcutForChord(event.chordName) ?? "?"
            }
        }
        return "·"
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
    
    private func getChordNameForBeat(_ beat: Int) -> String? {
        if let event = appData.autoPlaySchedule.first(where: { $0.triggerBeat == beat }) {
            return event.chordName
        }
        return nil
    }
    
    // 获取当前应该显示的歌词（提前两拍显示）
    private func getCurrentLyric() -> Lyric? {
        let currentBeat = currentTotalBeat
        let previewBeat = currentBeat + 1 // 提前一拍
        
        // 查找在预览拍号范围内的歌词
        let candidateLyrics = appData.performanceConfig.lyrics.filter { lyric in
            lyric.timeRanges.contains { range in
                previewBeat >= range.startBeat && previewBeat <= range.endBeat
            }
        }
        
        // 如果有多个候选歌词，选择开始拍号最晚的（优先级最高的）
        return candidateLyrics.max { lyric1, lyric2 in
            let maxStart1 = lyric1.timeRanges.compactMap { range in
                previewBeat >= range.startBeat && previewBeat <= range.endBeat ? range.startBeat : nil
            }.max() ?? Int.min
            
            let maxStart2 = lyric2.timeRanges.compactMap { range in
                previewBeat >= range.startBeat && previewBeat <= range.endBeat ? range.startBeat : nil
            }.max() ?? Int.min
            
            return maxStart1 < maxStart2
        }
    }
    
    // 获取下一句歌词（预览）
    private func getNextLyric() -> Lyric? {
        let currentBeat = currentTotalBeat
        let previewBeat = currentBeat + 2
        
        // 查找在预览拍号之后开始的歌词
        let upcomingLyrics = appData.performanceConfig.lyrics.filter { lyric in
            lyric.timeRanges.contains { range in
                range.startBeat > previewBeat
            }
        }.sorted { lyric1, lyric2 in
            // 获取每个歌词最早的开始拍号
            let earliestStart1 = lyric1.timeRanges.compactMap { range in
                range.startBeat > previewBeat ? range.startBeat : nil
            }.min() ?? Int.max
            
            let earliestStart2 = lyric2.timeRanges.compactMap { range in
                range.startBeat > previewBeat ? range.startBeat : nil
            }.min() ?? Int.max
            
            return earliestStart1 < earliestStart2
        }
        
        return upcomingLyrics.first
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                // 节拍时间轴
                HStack(spacing: 0) {
                    let indices = Array(0..<6) // 显示6个位置：提前两拍，当前拍，后续三拍
                    ForEach(indices, id: \.self) { index in
                        TimingBeatView(
                            index: index,
                            appData: appData,
                            keyboardHandler: keyboardHandler,
                            calculateBeatForIndex: calculateBeatForIndex,
                            getContentForBeat: getContentForBeat,
                            getChordNameForBeat: getChordNameForBeat
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                
                // 歌词显示区域
                if let currentLyric = getCurrentLyric() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentLyric.content)
                            .font(.title3)
                            .foregroundColor(.primary)
                            .fontWeight(.medium)
                        
                        if let nextLyric = getNextLyric() {
                            Text(nextLyric.content)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .opacity(0.7)
                        }
                    }
                    .padding(.top, 8)
                } else if let nextLyric = getNextLyric() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("即将到来")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(nextLyric.content)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                    }
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            
            if appData.totalMeasures > 0 {
                Text("\(appData.currentMeasure) / \(appData.totalMeasures)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Material.thin, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(height: 120)
    }
}

struct TimingBeatView: View {
    let index: Int
    let appData: AppData
    let keyboardHandler: KeyboardHandler
    let calculateBeatForIndex: (Int) -> Int
    let getContentForBeat: (Int) -> String
    let getChordNameForBeat: (Int) -> String?
    
    var body: some View {
        let beatForIndex = calculateBeatForIndex(index)
        let content = getContentForBeat(beatForIndex)
        let isCurrentBeat = index == 2 // 第3个位置是当前拍（提前一拍提醒）
        
        // 根据播放模式确定高亮逻辑
        let shouldHighlight: Bool = {
            if appData.playingMode == .assisted {
                // 辅助模式：只有当用户按下正确按键时才高亮
                return isCurrentBeat && content != "·" && appData.currentActivePositionTriggered
            } else if appData.playingMode == .automatic {
                // 自动模式：当前拍自动高亮（模拟按键按下效果）
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
    let shouldHighlightForAction: Bool // 是否需要强调提示用户按键
    
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
