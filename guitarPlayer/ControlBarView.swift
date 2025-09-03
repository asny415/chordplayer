import SwiftUI
import CoreMIDI

// MARK: - Reusable Views

struct ControlStripLabel: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.bottom, -4) // Adjust spacing
    }
}

struct StyledPicker<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let items: [T]
    let display: (T) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                ControlStripLabel(title: title)
            }
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

// MARK: - Main Control Bar View

struct ControlBarView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    // A computed property for the drum patterns available for the current time signature
    private var availableDrumPatterns: [String] {
        guard let patterns = appData.drumPatternLibrary?[appData.performanceConfig.timeSignature] else {
            return []
        }
        // Return sorted keys for a consistent order
        return patterns.keys.sorted()
    }
    
    // A custom binding to safely handle the optional drum pattern
    private var drumPatternBinding: Binding<String> {
        Binding<String>(
            get: {
                // Use the configured pattern, or fall back to the first available if nil
                appData.performanceConfig.drumPattern ?? availableDrumPatterns.first ?? ""
            },
            set: { newValue in
                appData.performanceConfig.drumPattern = newValue
            }
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            // --- DRUM CONTROL GROUP ---
            VStack(alignment: .leading, spacing: 4) {
                ControlStripLabel(title: "Drum Machine")
                HStack(spacing: 8) {
                    Button(action: {
                        if drumPlayer.isPlaying {
                            drumPlayer.stop()
                        } else {
                            drumPlayer.playPattern(tempo: keyboardHandler.currentTempo, velocity: 100, durationMs: 200)
                        }
                    }) {
                        Image(systemName: drumPlayer.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(drumPlayer.isPlaying ? .red : .green)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(midiManager.selectedOutput == nil && !drumPlayer.isPlaying)

                    StyledPicker(
                        title: "", // Title is implicit via the group label
                        selection: drumPatternBinding,
                        items: availableDrumPatterns,
                        display: { patternKey in
                            appData.drumPatternLibrary?[appData.performanceConfig.timeSignature]?[patternKey]?.displayName ?? patternKey
                        }
                    )
                    .frame(width: 180)
                }
            }
            
            // --- GLOBAL MUSIC SETTINGS ---
            HStack(spacing: 12) {
                StyledPicker(
                    title: "Key",
                    selection: $appData.performanceConfig.key,
                    items: appData.KEY_CYCLE,
                    display: { $0 }
                )
                
                StyledPicker(
                    title: "Time Sig",
                    selection: $appData.performanceConfig.timeSignature,
                    items: appData.TIME_SIGNATURE_CYCLE,
                    display: { $0 }
                )
                .onChange(of: appData.performanceConfig.timeSignature) { _, newTimeSig in
                    // When time signature changes, select a default pattern for the new signature
                    switch newTimeSig {
                    case "4/4":
                        appData.performanceConfig.drumPattern = "ROCK_4_4_BASIC"
                    case "3/4":
                        appData.performanceConfig.drumPattern = "WALTZ_3_4_BASIC"
                    case "6/8":
                        appData.performanceConfig.drumPattern = "SHUFFLE_6_8_BASIC"
                    default:
                        // Fallback to the first available pattern for the new time signature
                        appData.performanceConfig.drumPattern = appData.drumPatternLibrary?[newTimeSig]?.keys.first
                    }
                }

                StyledPicker(
                    title: "Quantize",
                    selection: Binding<String>(
                        get: { appData.performanceConfig.quantize ?? QuantizationMode.none.rawValue },
                        set: { appData.performanceConfig.quantize = $0 }
                    ),
                    items: QuantizationMode.allCases.map { $0.rawValue },
                    display: { rawValue in
                        QuantizationMode(rawValue: rawValue)?.displayName ?? rawValue
                    }
                )
            }
            
            Spacer()
            
            // --- MIDI OUTPUT & TEMPO ---
            HStack(spacing: 16) {
                // Tempo Control
                VStack(alignment: .leading, spacing: 4) {
                    ControlStripLabel(title: "BPM: \(Int(appData.performanceConfig.tempo))")
                    HStack(spacing: 8) {
                        Slider(
                            value: $appData.performanceConfig.tempo,
                            in: 60...240,
                            step: 1,
                            onEditingChanged: { _ in metronome.tempo = appData.performanceConfig.tempo }
                        )
                        Stepper("BPM",
                            value: $appData.performanceConfig.tempo,
                            in: 60...240,
                            step: 1,
                            onEditingChanged: { _ in metronome.tempo = appData.performanceConfig.tempo }
                        ).labelsHidden()
                    }
                }
                .frame(width: 180)
                
                // MIDI Output
                StyledPicker(
                    title: "MIDI Output",
                    selection: $midiManager.selectedOutput,
                    items: [nil] + midiManager.availableOutputs,
                    display: { endpoint in
                        endpoint.map { midiManager.displayName(for: $0) } ?? "None"
                    }
                )
                .frame(width: 160)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.2))
        .focusable(false)
    }
}
