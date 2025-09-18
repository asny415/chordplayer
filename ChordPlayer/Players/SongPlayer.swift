import Foundation
import Combine

class PresetArrangerPlayer: ObservableObject {
    // Dependencies
    private var midiManager: MidiManager
    var appData: AppData
    var chordPlayer: ChordPlayer
    var drumPlayer: DrumPlayer
    var soloPlayer: SoloPlayer

    // Playback State
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0 // 当前播放位置（拍数）
    @Published var isLooping: Bool = false
    @Published var loopStartBeat: Double = 0
    @Published var loopEndBeat: Double = 0

    private var playbackStartTime: TimeInterval?
    private var playbackTimer: Timer?
    private var scheduledEvents: [UUID] = []
    private var currentPreset: Preset?

    init(midiManager: MidiManager, appData: AppData, chordPlayer: ChordPlayer, drumPlayer: DrumPlayer, soloPlayer: SoloPlayer) {
        self.midiManager = midiManager
        self.appData = appData
        self.chordPlayer = chordPlayer
        self.drumPlayer = drumPlayer
        self.soloPlayer = soloPlayer
    }

    // MARK: - Playback Control

    func play(preset: Preset, startFromBeat: Double = 0) {
        if isPlaying {
            stop()
            return
        }

        currentPreset = preset
        playbackPosition = startFromBeat
        isPlaying = true
        playbackStartTime = ProcessInfo.processInfo.systemUptime

        // 安排播放事件
        scheduleAllEvents(for: preset, startBeat: startFromBeat)

        // 启动播放位置更新定时器
        startPlaybackTimer(bpm: preset.bpm)
    }

    func playCurrentPresetArrangement(startFromBeat: Double = 0) {
        guard let preset = appData.preset else { return }
        play(preset: preset, startFromBeat: startFromBeat)
    }

    func stop() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartTime = nil

        // 停止所有播放器
        chordPlayer.panic()
        drumPlayer.stop()
        soloPlayer.stopPlayback()

        // 取消所有计划的事件
        for eventId in scheduledEvents {
            midiManager.cancelScheduledEvent(id: eventId)
        }
        scheduledEvents.removeAll()

        playbackPosition = 0
    }

    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil

        // 停止所有播放器但保持位置
        chordPlayer.panic()
        drumPlayer.stop()
        soloPlayer.stopPlayback()
    }

    func resume() {
        guard let preset = currentPreset else { return }
        isPlaying = true
        playbackStartTime = ProcessInfo.processInfo.systemUptime - (playbackPosition * 60.0 / preset.bpm)

        // 重新安排从当前位置开始的事件
        scheduleAllEvents(for: preset, startBeat: playbackPosition)
        startPlaybackTimer(bpm: preset.bpm)
    }

    func seekTo(beat: Double) {
        let wasPlaying = isPlaying
        if isPlaying {
            pause()
        }
        playbackPosition = beat
        if wasPlaying {
            resume()
        }
    }

    func setLoop(startBeat: Double, endBeat: Double) {
        loopStartBeat = startBeat
        loopEndBeat = endBeat
        isLooping = true
    }

    func clearLoop() {
        isLooping = false
        loopStartBeat = 0
        loopEndBeat = 0
    }

    // MARK: - Private Methods

    private func startPlaybackTimer(bpm: Double) {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.playbackStartTime,
                  let preset = self.currentPreset else { return }

            let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime
            let beatsPerSecond = bpm / 60.0
            self.playbackPosition = elapsedTime * beatsPerSecond

            // 检查是否需要循环
            if self.isLooping && self.playbackPosition >= self.loopEndBeat {
                self.seekTo(beat: self.loopStartBeat)
                return
            }

            // 检查是否播放结束
            if self.playbackPosition >= preset.arrangement.lengthInBeats {
                self.stop()
            }
        }
    }

    private func scheduleAllEvents(for preset: Preset, startBeat: Double) {
        let beatsToSeconds = 60.0 / preset.bpm
        let currentTime = ProcessInfo.processInfo.systemUptime

        // 清除之前的事件
        for eventId in scheduledEvents {
            midiManager.cancelScheduledEvent(id: eventId)
        }
        scheduledEvents.removeAll()

        // 安排鼓机事件
        scheduleDrumEvents(track: preset.arrangement.drumTrack, preset: preset, startBeat: startBeat, currentTime: currentTime, beatsToSeconds: beatsToSeconds)

        // 安排吉他事件
        for guitarTrack in preset.arrangement.guitarTracks where !guitarTrack.isMuted {
            let shouldPlaySolo = guitarTrack.isSolo || preset.arrangement.guitarTracks.allSatisfy { !$0.isSolo }
            if shouldPlaySolo {
                scheduleGuitarEvents(track: guitarTrack, preset: preset, startBeat: startBeat, currentTime: currentTime, beatsToSeconds: beatsToSeconds)
            }
        }
    }

    private func scheduleDrumEvents(track: DrumTrack, preset: Preset, startBeat: Double, currentTime: TimeInterval, beatsToSeconds: Double) {
        guard !track.isMuted else { return }

        for segment in track.segments {
            // 只处理在播放范围内的片段
            guard segment.startBeat + segment.durationInBeats > startBeat &&
                  segment.startBeat < preset.arrangement.lengthInBeats else { continue }

            guard let drumPattern = appData.getDrumPattern(for: segment.patternId) else { continue }

            let segmentStartTime = currentTime + (max(segment.startBeat, startBeat) - startBeat) * beatsToSeconds
            let segmentDuration = min(segment.durationInBeats, preset.arrangement.lengthInBeats - segment.startBeat) * beatsToSeconds

            // 计算需要重复播放pattern多少次
            let patternDurationBeats = Double(drumPattern.length) / (drumPattern.resolution == .sixteenth ? 4.0 : 2.0)
            let patternDurationSeconds = patternDurationBeats * beatsToSeconds
            let repeatCount = Int(ceil(segmentDuration / patternDurationSeconds))

            for repeatIndex in 0..<repeatCount {
                let repeatStartTime = segmentStartTime + Double(repeatIndex) * patternDurationSeconds
                if repeatStartTime >= currentTime {
                    scheduleDrumPattern(pattern: drumPattern, startTime: repeatStartTime, volume: track.volume)
                }
            }
        }
    }

    private func scheduleDrumPattern(pattern: DrumPattern, startTime: TimeInterval, volume: Double) {
        let stepDuration = (60.0 / (currentPreset?.bpm ?? 120.0)) / Double(pattern.length / 4) // 假设16th notes per bar

        for stepIndex in 0..<pattern.length {
            for (instrumentIndex, instrumentRow) in pattern.patternGrid.enumerated() {
                if instrumentRow[stepIndex] {
                    let noteTime = startTime + Double(stepIndex) * stepDuration
                    let midiNote = pattern.midiNotes[instrumentIndex]
                    let velocity = UInt8(min(127, max(1, Int(100 * volume))))

                    let eventId = midiManager.scheduleNoteOn(
                        note: UInt8(midiNote),
                        velocity: velocity,
                        channel: UInt8(appData.drumMidiChannel - 1),
                        scheduledUptimeMs: noteTime * 1000
                    )
                    scheduledEvents.append(eventId)

                    let offEventId = midiManager.scheduleNoteOff(
                        note: UInt8(midiNote),
                        velocity: 0,
                        channel: UInt8(appData.drumMidiChannel - 1),
                        scheduledUptimeMs: (noteTime + 0.1) * 1000
                    )
                    scheduledEvents.append(offEventId)
                }
            }
        }
    }

    private func scheduleGuitarEvents(track: GuitarTrack, preset: Preset, startBeat: Double, currentTime: TimeInterval, beatsToSeconds: Double) {
        for segment in track.segments {
            // 只处理在播放范围内的片段
            guard segment.startBeat + segment.durationInBeats > startBeat &&
                  segment.startBeat < preset.arrangement.lengthInBeats else { continue }

            let segmentStartTime = currentTime + (max(segment.startBeat, startBeat) - startBeat) * beatsToSeconds

            switch segment.type {
            case .solo(let segmentId):
                if let soloSegment = appData.getSoloSegment(for: segmentId) {
                    scheduleSoloSegment(segment: soloSegment, startTime: segmentStartTime, volume: track.volume, pan: track.pan)
                }

            case .accompaniment(let segmentId):
                if let accompSegment = appData.getAccompanimentSegment(for: segmentId) {
                    scheduleAccompanimentSegment(segment: accompSegment, startTime: segmentStartTime, volume: track.volume, pan: track.pan, preset: preset)
                }
            }
        }
    }

    private func scheduleSoloSegment(segment: SoloSegment, startTime: TimeInterval, volume: Double, pan: Double) {
        // 这里简化实现，实际应该使用SoloPlayer的逻辑
        guard let preset = currentPreset else { return }
        let beatsToSeconds = 60.0 / preset.bpm

        for note in segment.notes {
            let noteStartTime = startTime + note.startTime * beatsToSeconds
            guard noteStartTime >= ProcessInfo.processInfo.systemUptime else { continue }

            let midiNote = 40 + note.string * 5 + note.fret // 简化的MIDI音符计算
            let velocity = UInt8(min(127, max(1, Int(Double(note.velocity) * volume))))

            let eventId = midiManager.scheduleNoteOn(
                note: UInt8(midiNote),
                velocity: velocity,
                channel: UInt8(appData.chordMidiChannel - 1),
                scheduledUptimeMs: noteStartTime * 1000
            )
            scheduledEvents.append(eventId)

            // 音符持续时间（简化为0.5秒）
            let offEventId = midiManager.scheduleNoteOff(
                note: UInt8(midiNote),
                velocity: 0,
                channel: UInt8(appData.chordMidiChannel - 1),
                scheduledUptimeMs: (noteStartTime + 0.5) * 1000
            )
            scheduledEvents.append(offEventId)
        }
    }

    private func scheduleAccompanimentSegment(segment: AccompanimentSegment, startTime: TimeInterval, volume: Double, pan: Double, preset: Preset) {
        // 这里应该使用ChordPlayer的逻辑来播放伴奏片段
        // 简化实现，只是占位
        // 实际实现中应该调用chordPlayer.play(segment: segment)并调整时间偏移
    }
}