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
    private let openStringMIDINotes: [UInt8] = [64, 59, 55, 50, 45, 40]

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
        guard !track.isMuted, !track.segments.isEmpty else { return }

        let sortedSegments = track.segments.sorted { $0.startBeat < $1.startBeat }

        for i in 0..<sortedSegments.count {
            let currentSegment = sortedSegments[i]
            
            // Determine the end beat for the current segment's loop
            let nextSegmentStartBeat = (i + 1 < sortedSegments.count) ? sortedSegments[i+1].startBeat : preset.arrangement.lengthInBeats
            let loopEndBeat = min(nextSegmentStartBeat, preset.arrangement.lengthInBeats)

            // Only process segments that are relevant to the current playback time
            guard currentSegment.startBeat < loopEndBeat && loopEndBeat > startBeat else { continue }
            
            guard let drumPattern = appData.getDrumPattern(for: currentSegment.patternId) else { continue }

            let segmentStartTime = currentTime + (max(currentSegment.startBeat, startBeat) - startBeat) * beatsToSeconds
            let segmentEffectiveDuration = (loopEndBeat - max(currentSegment.startBeat, startBeat)) * beatsToSeconds
            
            guard segmentEffectiveDuration > 0 else { continue }

            let patternDurationBeats = Double(drumPattern.length) / (drumPattern.resolution == .sixteenth ? 4.0 : 2.0)
            let patternDurationSeconds = patternDurationBeats * beatsToSeconds
            
            guard patternDurationSeconds > 0 else { continue }
            
            let repeatCount = Int(ceil(segmentEffectiveDuration / patternDurationSeconds))

            for repeatIndex in 0..<repeatCount {
                let repeatStartTime = segmentStartTime + Double(repeatIndex) * patternDurationSeconds
                // Ensure we don't schedule past the loop end time
                if repeatStartTime < (segmentStartTime + segmentEffectiveDuration) && repeatStartTime >= currentTime {
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
                    scheduleSoloSegment(segment: soloSegment, startTime: segmentStartTime, track: track)
                }

            case .accompaniment(let segmentId):
                if let accompSegment = appData.getAccompanimentSegment(for: segmentId) {
                    scheduleAccompanimentSegment(segment: accompSegment, startTime: segmentStartTime, track: track, preset: preset)
                }
            }
        }
    }

    private func scheduleSoloSegment(segment: SoloSegment, startTime: TimeInterval, track: GuitarTrack) {
        // 这里简化实现，实际应该使用SoloPlayer的逻辑
        guard let preset = currentPreset else { return }
        let beatsToSeconds = 60.0 / preset.bpm

        for note in segment.notes {
            let noteStartTime = startTime + note.startTime * beatsToSeconds
            guard noteStartTime >= ProcessInfo.processInfo.systemUptime else { continue }

            let midiNote = self.midiNote(from: note.string, fret: note.fret)
            let velocity = UInt8(min(127, max(1, Int(Double(note.velocity) * track.volume))))

            let eventId = midiManager.scheduleNoteOn(
                note: UInt8(midiNote),
                velocity: velocity,
                channel: UInt8(track.midiChannel - 1),
                scheduledUptimeMs: noteStartTime * 1000
            )
            scheduledEvents.append(eventId)

            // 音符持续时间（简化为0.5秒）
            let offEventId = midiManager.scheduleNoteOff(
                note: UInt8(midiNote),
                velocity: 0,
                channel: UInt8(track.midiChannel - 1),
                scheduledUptimeMs: (noteStartTime + 0.5) * 1000
            )
            scheduledEvents.append(offEventId)
        }
    }

    private func scheduleAccompanimentSegment(segment: AccompanimentSegment, startTime: TimeInterval, track: GuitarTrack, preset: Preset) {
        let secondsPerBeat = 60.0 / preset.bpm

        // Create a flat, time-sorted list of all chord events with their absolute start times.
        let absoluteChordEvents = segment.measures.enumerated().flatMap { (measureIndex, measure) -> [TimelineEvent] in
            measure.chordEvents.map { event in
                var absoluteEvent = event
                absoluteEvent.startBeat += measureIndex * preset.timeSignature.beatsPerMeasure
                return absoluteEvent
            }
        }.sorted { $0.startBeat < $1.startBeat }

        // Iterate through each measure and its pattern events.
        for (measureIndex, measure) in segment.measures.enumerated() {
            for patternEvent in measure.patternEvents {
                let absolutePatternStartBeat = measureIndex * preset.timeSignature.beatsPerMeasure + patternEvent.startBeat

                // Find the chord that should be active for this pattern event.
                let activeChordEvent = absoluteChordEvents.last { $0.startBeat <= absolutePatternStartBeat }

                guard let chordEvent = activeChordEvent else { continue }
                
                // Find the actual Chord and GuitarPattern objects from the preset library.
                guard let chordToPlay = preset.chords.first(where: { $0.id == chordEvent.resourceId }),
                      let patternToPlay = preset.playingPatterns.first(where: { $0.id == patternEvent.resourceId }) else {
                    continue
                }

                let scheduledUptime = startTime + (Double(absolutePatternStartBeat) * secondsPerBeat)
                let totalDuration = Double(patternEvent.durationInBeats) * secondsPerBeat

                // Ensure we don't schedule events in the past
                if scheduledUptime < ProcessInfo.processInfo.systemUptime {
                    continue
                }

                chordPlayer.schedulePattern(
                    chord: chordToPlay,
                    pattern: patternToPlay,
                    preset: preset,
                    scheduledUptime: scheduledUptime,
                    totalDuration: totalDuration,
                    dynamics: measure.dynamics,
                    midiChannel: track.midiChannel
                )
            }
        }
    }

    private func midiNote(from string: Int, fret: Int) -> UInt8 {
        guard string >= 0 && string < openStringMIDINotes.count else { return 0 }
        return openStringMIDINotes[string] + UInt8(fret)
    }
}