import SwiftUI

struct GlobalSettingsView: View {
    @EnvironmentObject var appData: AppData
    @Binding var isPlayingKaraoke: Bool
    @Binding var playheadPosition: Double
    
    // Define constants for cycles locally
    private let KEY_CYCLE = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let TIME_SIGNATURE_OPTIONS = [TimeSignature(beatsPerMeasure: 4, beatUnit: 4), 
                                          TimeSignature(beatsPerMeasure: 3, beatUnit: 4), 
                                          TimeSignature(beatsPerMeasure: 6, beatUnit: 8)]

    var body: some View {
        if appData.preset != nil {
            let tempoBinding = Binding<Double>(
                get: { appData.preset?.bpm ?? 120.0 },
                set: { newValue in
                    appData.preset?.bpm = newValue
                    appData.saveChanges()
                }
            )
            
            let keyBinding = Binding<String>(
                get: { appData.preset?.key ?? "C" },
                set: { newValue in
                    appData.preset?.key = newValue
                    appData.saveChanges()
                }
            )

            let timeSignatureBinding = Binding<TimeSignature>(
                get: { appData.preset?.timeSignature ?? TimeSignature() },
                set: { newValue in
                    appData.preset?.timeSignature = newValue
                    appData.saveChanges()
                }
            )

            HStack(spacing: 12) {
                DraggableValueCard(label: "Key", selection: keyBinding, options: KEY_CYCLE)
                    .frame(maxWidth: .infinity)

                // Time signature selector
                DraggableValueCard(label: "Time Sig", selection: timeSignatureBinding, options: TIME_SIGNATURE_OPTIONS)
                    .frame(maxWidth: .infinity)

                // Tempo card
                TempoDashboardCard(tempo: tempoBinding)
                    .frame(maxWidth: .infinity)

                // Song Arrangement Playback Card
                ArrangementPlaybackCard(playheadPosition: $playheadPosition, isPlayingKaraoke: $isPlayingKaraoke)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        } else {
            Text("No preset loaded. Please select or create a preset.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Custom Control Views (some might need minor updates)

struct DashboardCardView: View {
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

struct TempoDashboardCard: View {
    @Binding var tempo: Double
    @State private var startTempo: Double? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DashboardCardView(label: "Tempo", value: "\(Int(round(tempo)))", unit: "BPM")
            
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(5)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if self.startTempo == nil { self.startTempo = self.tempo }
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

struct DraggableValueCard<T: Equatable & CustomStringConvertible>: View {
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
                    if self.startIndex == nil { self.startIndex = currentIndex }
                    
                    let dragAmount = value.translation.width
                    let indexOffset = Int(round(dragAmount / 30.0))
                    
                    let newIndex = self.startIndex! + indexOffset
                    let clampedIndex = max(0, min(options.count - 1, newIndex))
                    
                    if options[clampedIndex] != selection {
                        self.selection = options[clampedIndex]
                    }
                }
                .onEnded { _ in self.startIndex = nil }
        )
    }
}

struct PlayingModeBadgeView: View {
    let playingMode: PlayingMode
    
    var body: some View {
        Text(playingMode.shortDisplay)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.secondary.opacity(0.15)))
    }
}

struct ArrangementPlaybackCard: View {
    @EnvironmentObject var chordPlayer: PresetArrangerPlayer
    @EnvironmentObject var appData: AppData
    
    @Binding var playheadPosition: Double
    @Binding var isPlayingKaraoke: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("Playback".uppercased())
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 2) {
                Text(chordPlayer.isPlaying ? "Playing" : "Stopped")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                
                if let currentPreset = appData.preset {
                    let totalBeats = currentPreset.arrangement.lengthInBeats
                    if totalBeats > 0 {
                        // Display the position from the player, which is the source of truth
                        Text(String(format: "%.1f / %.1f", chordPlayer.playbackPosition, totalBeats))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .foregroundColor(chordPlayer.isPlaying ? .green : .primary)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if chordPlayer.isPlaying {
                chordPlayer.stop()
                isPlayingKaraoke = false // Also stop karaoke view
            } else {
                // 如果当前位置小于1拍，从头开始播放，否则，从当前位置开始播放
                if playheadPosition < 1.0 {
                    chordPlayer.play()
                    isPlayingKaraoke = true // Also start karaoke view
                } else {
                    // Seek to the UI's playhead position, then play from there.
                    chordPlayer.seekTo(beat: playheadPosition)
                    chordPlayer.playFromCurrentPosition()
                    isPlayingKaraoke = true // Also start karaoke view
                }
            }
        }
        .onChange(of: chordPlayer.isPlaying) { _,newIsPlaying in
            // If the sequencer stops playing for any reason (e.g., song ends),
            // ensure we exit the karaoke view.
            if !newIsPlaying {
                isPlayingKaraoke = false
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(chordPlayer.isPlaying ? Color.green : Color.secondary.opacity(0.2), lineWidth: chordPlayer.isPlaying ? 2.5 : 1)
        )
    }
}

// Make TimeSignature conform to CustomStringConvertible for the DraggableValueCard
extension TimeSignature: CustomStringConvertible {
    public var description: String { "\(beatsPerMeasure)/\(beatUnit)" }
}
