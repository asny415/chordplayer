import SwiftUI
import CoreMIDI

// MARK: - Main Control Bar View

struct ControlBarView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var chordPlayer: ChordPlayer
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
        Form {
            // --- DRUM CONTROL GROUP ---
            Section(header: Text("control_bar_drum_machine_header")) {
                HStack {
                    Button(action: {
                        if drumPlayer.isPlaying {
                            drumPlayer.stop()
                        } else {
                            drumPlayer.playPattern(tempo: keyboardHandler.currentTempo, velocity: 100, durationMs: 200)
                        }
                    }) {
                        Image(systemName: drumPlayer.isPlaying ? "stop.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(drumPlayer.isPlaying ? .red : .green)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(midiManager.selectedOutput == nil && !drumPlayer.isPlaying)

                    Picker("control_bar_pattern_picker_label", selection: drumPatternBinding) {
                        ForEach(availableDrumPatterns, id: \.self) { patternKey in
                            Text(appData.drumPatternLibrary?[appData.performanceConfig.timeSignature]?[patternKey]?.displayName ?? patternKey).tag(patternKey)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            // --- GLOBAL MUSIC SETTINGS ---
            Section(header: Text("control_bar_global_settings_header")) {
                Picker("control_bar_key_picker_label", selection: $appData.performanceConfig.key) {
                    ForEach(appData.KEY_CYCLE, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                
                Picker("control_bar_time_sig_picker_label", selection: $appData.performanceConfig.timeSignature) {
                    ForEach(appData.TIME_SIGNATURE_CYCLE, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
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

                Picker("control_bar_quantize_picker_label", selection: Binding<String>(
                    get: { appData.performanceConfig.quantize ?? QuantizationMode.none.rawValue },
                    set: { appData.performanceConfig.quantize = $0 }
                )) {
                    ForEach(QuantizationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
            }
            
            // --- MIDI OUTPUT & TEMPO ---
            Section(header: Text("control_bar_tempo_midi_header")) {
                HStack { // Use HStack for horizontal layout
                    Text("control_bar_bpm_label")
                    // Display current tempo
                    Text("\(Int(appData.performanceConfig.tempo))")
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .trailing) // Give it a fixed width for alignment

                    // Stepper for fine adjustment
                    Stepper("", // Empty label as "BPM" is already displayed
                        value: $appData.performanceConfig.tempo,
                        in: 10...240,
                        step: 1,
                        onEditingChanged: { _ in metronome.tempo = appData.performanceConfig.tempo }
                    ).labelsHidden() // Hide default label

                    // Slider for coarse adjustment
                    Slider(
                        value: $appData.performanceConfig.tempo,
                        in: 10...240,
                        step: 1,
                        onEditingChanged: { _ in metronome.tempo = appData.performanceConfig.tempo }
                    )
                }
                
                Picker("control_bar_midi_output_picker_label", selection: $midiManager.selectedOutput) {
                    Text("control_bar_midi_output_none_option").tag(MIDIEndpointRef?.none)
                    ForEach(midiManager.availableOutputs, id: \.self) { endpoint in
                        Text(midiManager.displayName(for: endpoint)).tag(MIDIEndpointRef?.some(endpoint))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .focusable(false)
    }
}