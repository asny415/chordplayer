import SwiftUI
import CoreMIDI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    // Use KeyboardHandler as single source-of-truth for keyboard-driven state
    @State private var isDrumPlaying: Bool = false

    

    @FocusState private var isFocused: Bool // Add this for focus management

    let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let timeSignatureNumerators = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    let timeSignatureDenominators = [2, 4, 8, 16]

    init() {
    // No local initial state; KeyboardHandler initializes runtime values
        // _keyboardHandler initialization removed from here
    }

    var body: some View {
        VStack(spacing: 10) {
            // MARK: - Top Control Bar
            HStack {
                // MIDI Device Selection
                Picker("MIDI Output", selection: $midiManager.selectedOutput) {
                    Text("None").tag(nil as MIDIEndpointRef?)
                    ForEach(midiManager.availableOutputs, id: \.self) {
                        Text(midiManager.displayName(for: $0)).tag($0 as MIDIEndpointRef?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Spacer()

                // Tempo Control (bound to KeyboardHandler.currentTempo)
                VStack {
                    Text("Tempo: \(Int(keyboardHandler.currentTempo)) BPM")
                    Slider(value: Binding(get: {
                        keyboardHandler.currentTempo
                    }, set: { new in
                        keyboardHandler.currentTempo = new
                        metronome.tempo = new
                    }), in: 60...240, step: 5) {
                        Text("Tempo")
                    } minimumValueLabel: { Text("60") } maximumValueLabel: { Text("240") }
                }
                .frame(width: 200)

                Spacer()

                // Time Signature Control - simplified to three choices
                Picker("Time Signature", selection: Binding(get: {
                    keyboardHandler.currentTimeSignature
                }, set: { new in
                    keyboardHandler.currentTimeSignature = new
                    let parts = new.split(separator: "/").map(String.init)
                    if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                        metronome.timeSignatureNumerator = num
                        metronome.timeSignatureDenominator = den
                    }
                })) {
                    ForEach(appData.TIME_SIGNATURE_CYCLE, id: \.self) { ts in
                        Text(ts).tag(ts)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 160)

                Spacer()

                // Key Control (synchronized with KeyboardHandler.currentKeyIndex)
                Picker("Key", selection: Binding(get: {
                    keyboardHandler.currentKeyIndex
                }, set: { new in
                    keyboardHandler.currentKeyIndex = new
                    // Optionally update appData performance config
                    appData.performanceConfig.key = appData.KEY_CYCLE[new]
                })) {
                    ForEach(0..<keys.count, id: \.self) { index in
                        Text(keys[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)

                Spacer()

                // Quantization Picker
                Picker("Quantize", selection: Binding(get: {
                    keyboardHandler.quantizationMode
                }, set: { new in
                    keyboardHandler.quantizationMode = new
                    appData.performanceConfig.quantize = new
                })) {
                    Text(QuantizationMode.none.rawValue).tag(QuantizationMode.none.rawValue)
                    Text(QuantizationMode.measure.rawValue).tag(QuantizationMode.measure.rawValue)
                    Text(QuantizationMode.halfMeasure.rawValue).tag(QuantizationMode.halfMeasure.rawValue)
                }
                .pickerStyle(.menu)
                .frame(minWidth: 140)

                Spacer()

                // Drum Machine Toggle (uses safe SF Symbols)
                Button(action: {
                    if drumPlayer.isPlaying {
                        drumPlayer.stop()
                    } else {
                        let timeSig = keyboardHandler.currentTimeSignature
                        drumPlayer.playPattern(patternName: "ROCK_4_4_BASIC", tempo: keyboardHandler.currentTempo, timeSignature: timeSig, velocity: 100, durationMs: 200)
                    }
                }) {
                    Label(drumPlayer.isPlaying ? "Stop Drums" : "Start Drums", systemImage: drumPlayer.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Divider()

            // MARK: - Chord Buttons
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    if let chordLibrary = appData.chordLibrary {
                        ForEach(chordLibrary.keys.sorted(), id: \.self) { chordName in
                            Button(action: {
                                // For now, use a default pattern. Will add pattern selection later.
                                guitarPlayer.playChord(chordName: chordName, pattern: appData.patternLibrary?["STRUM_FAST_4_4_1_4"] ?? []) // Updated call
                            }) {
                                Text(chordName.replacingOccurrences(of: "_", with: " "))
                                    .font(.headline)
                                    .padding()
                                    .frame(maxWidth: .infinity, minHeight: 60)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text("Loading chords...")
                    }
                }
                .padding()
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600) // Set a reasonable window size
        .focusable()
        .focused($isFocused) // Apply focus state
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true // Request focus when view appears
                // Initialize KeyboardHandler here with actual environment objects
                // Ensure KeyboardHandler state matches persisted AppData on first appearance
                keyboardHandler.currentTimeSignature = appData.performanceConfig.timeSignature
                keyboardHandler.currentTempo = appData.performanceConfig.tempo
                // Sync metronome to appData values
                let parts = appData.performanceConfig.timeSignature.split(separator: "/").map(String.init)
                if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                    metronome.timeSignatureNumerator = num
                    metronome.timeSignatureDenominator = den
                }
                metronome.tempo = appData.performanceConfig.tempo
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppData())
        .environmentObject(MidiManager())
        .environmentObject(Metronome(midiManager: MidiManager())) // Pass a dummy MidiManager for preview
        .environmentObject(GuitarPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData())) // Dummy for preview
        .environmentObject(DrumPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData())) // Dummy for preview
        .environmentObject(KeyboardHandler(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), guitarPlayer: GuitarPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData()), drumPlayer: DrumPlayer(midiManager: MidiManager(), metronome: Metronome(midiManager: MidiManager()), appData: AppData()), appData: AppData()))
}
