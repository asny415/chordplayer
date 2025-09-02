import SwiftUI
import CoreMIDI

// MARK: - Reusable Views

struct ControlStripLabel: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, -2)
    }
}

struct StyledPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let items: [T]
    let display: (T) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ControlStripLabel(title: title)
            Picker(title, selection: $selection) {
                ForEach(items, id: \.self) { item in
                    Text(display(item)).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.15))
            .cornerRadius(8)
            .accentColor(.cyan)
        }
    }
}

struct ControlBarView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    private var keys: [String] {
        appData.KEY_CYCLE
    }

    var body: some View {
        HStack(spacing: 16) {
            // MIDI Output
            StyledPicker(
                title: "MIDI Output",
                selection: $midiManager.selectedOutput,
                items: [nil] + midiManager.availableOutputs,
                display: { endpoint in
                    // Provide a clear label when no endpoint is selected
                    endpoint.map { midiManager.displayName(for: $0) } ?? "None"
                }
            )
            .frame(width: 160)
            .disabled(midiManager.availableOutputs.isEmpty) // disable when no outputs
            
            // Pickers Group
            HStack(spacing: 12) {
                StyledPicker(title: "Key", selection: Binding(get: { keyboardHandler.currentKeyIndex }, set: { keyboardHandler.currentKeyIndex = $0 }), items: Array(0..<keys.count)) { keys[$0] }
                
                StyledPicker(title: "Time Sig", selection: Binding(get: { keyboardHandler.currentTimeSignature }, set: { keyboardHandler.currentTimeSignature = $0 }), items: appData.TIME_SIGNATURE_CYCLE) { $0 }

                StyledPicker(title: "Group", selection: Binding(get: { keyboardHandler.currentGroupIndex }, set: { keyboardHandler.currentGroupIndex = $0 }), items: Array(0..<appData.performanceConfig.patternGroups.count)) { appData.performanceConfig.patternGroups[$0].name }
                
                StyledPicker(title: "Quantize", selection: Binding(get: { keyboardHandler.quantizationMode }, set: { keyboardHandler.quantizationMode = $0; appData.performanceConfig.quantize = $0 }), items: QuantizationMode.allCases.map { $0.rawValue }) { $0 }
            }
            
            Spacer()
            
            // Tempo Control
            VStack(alignment: .leading, spacing: 4) {
                ControlStripLabel(title: "BPM: \(Int(keyboardHandler.currentTempo))")
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { keyboardHandler.currentTempo }, set: { keyboardHandler.currentTempo = $0; metronome.tempo = $0 }), in: 60...240, step: 1)
                    Stepper("BPM", value: Binding(get: { keyboardHandler.currentTempo }, set: { keyboardHandler.currentTempo = $0; metronome.tempo = $0 }), in: 60...240, step: 1).labelsHidden()
                }
            }
            .frame(width: 180)
            
            // Drum Machine Toggle
            VStack(spacing: 4) {
                ControlStripLabel(title: "Drum Machine")
                Button(action: {
                    if drumPlayer.isPlaying {
                        drumPlayer.stop()
                    } else {
                        drumPlayer.playPattern(patternName: "ROCK_4_4_BASIC", tempo: keyboardHandler.currentTempo, timeSignature: keyboardHandler.currentTimeSignature, velocity: 100, durationMs: 200)
                    }
                }) {
                    Image(systemName: drumPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(drumPlayer.isPlaying ? .red : .green)
                }
                .disabled(midiManager.availableOutputs.isEmpty && !drumPlayer.isPlaying) // disable play when no MIDI output available
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .focusable(false)
        .background(FrameLogger(name: "controlBar"))
    }
}