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

    

    // Removed root FocusState to avoid macOS focus ring around the whole view

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

                // Current Pattern Group (e.g., Intro / Verse / Chorus)
                Picker("Group", selection: Binding(get: {
                    keyboardHandler.currentGroupIndex
                }, set: { new in
                    keyboardHandler.currentGroupIndex = new
                })) {
                    ForEach(0..<appData.performanceConfig.patternGroups.count, id: \.self) { idx in
                        Text(appData.performanceConfig.patternGroups[idx].name).tag(idx)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 160)

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
                .focusable(false)
            }
            .padding(.horizontal)
            .focusable(false)

            Divider()

            // MARK: - Chord Buttons
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    if let chordLibrary = appData.chordLibrary {
                        ForEach(chordLibrary.keys.sorted(), id: \.self) { chordName in
                            Button(action: {
                                // Route button press through KeyboardHandler so group/pattern resolution is consistent with keyboard
                                keyboardHandler.playChordButton(chordName: chordName)
                            }) {
                                Text(chordLabel(chordName))
                                    .font(.headline)
                                    .padding()
                                    .frame(minWidth: 100, minHeight: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(keyboardHandler.activeChordName == chordName ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.12))
                                    )
                                    .scaleEffect(keyboardHandler.activeChordName == chordName ? 1.03 : 1.0)
                                    .shadow(color: keyboardHandler.activeChordName == chordName ? Color.black.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .animation(.easeOut(duration: 0.18))
                        }
                    } else {
                        Text("Loading chords...")
                    }
                }
                .padding()
            }
        .focusable(false)
        }
    .background(Color(nsColor: NSColor.windowBackgroundColor))
    .focusable(false)
    .padding()
        .frame(minWidth: 800, minHeight: 600) // Set a reasonable window size
        .onAppear {
            DispatchQueue.main.async {
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

    // Format chord name for display: show Major chords as simple letters (C, C#, etc.)
    private func chordLabel(_ chordName: String) -> String {
        // If exact suffix _Major, display root only
        if chordName.hasSuffix("_Major") {
            var root = chordName.replacingOccurrences(of: "_Major", with: "")
            // Convert _Sharp -> # and remove remaining underscores
            root = root.replacingOccurrences(of: "_Sharp", with: "#")
            root = root.replacingOccurrences(of: "_", with: "")
            return root
        }
        // Otherwise, show readable name, convert _Sharp to # for compactness
        var label = chordName.replacingOccurrences(of: "_Sharp", with: "#")
        label = label.replacingOccurrences(of: "_", with: " ")
        return label
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
