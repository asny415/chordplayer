import SwiftUI
import CoreMIDI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer

    @State private var selectedTempo: Double
    @State private var selectedTimeSignatureNumerator: Int
    @State private var selectedTimeSignatureDenominator: Int
    @State private var selectedKeyIndex: Int = 0 // For now, just an index
    @State private var isMetronomePlaying: Bool = false
    @State private var isDrumPlaying: Bool = false

    

    @FocusState private var isFocused: Bool // Add this for focus management

    let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    let timeSignatureNumerators = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    let timeSignatureDenominators = [2, 4, 8, 16]

    init() {
        _selectedTempo = State(initialValue: 120.0)
        _selectedTimeSignatureNumerator = State(initialValue: 4)
        _selectedTimeSignatureDenominator = State(initialValue: 4)
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

                // Tempo Control
                VStack {
                    Text("Tempo: \(Int(selectedTempo)) BPM")
                    Slider(value: $selectedTempo, in: 60...240, step: 5) {
                        Text("Tempo")
                    } minimumValueLabel: { Text("60") } maximumValueLabel: { Text("240") }
                    .onChange(of: selectedTempo) { newValue in
                        metronome.tempo = newValue
                    }
                }
                .frame(width: 200)

                Spacer()

                // Time Signature Control
                HStack {
                    Picker("Numerator", selection: $selectedTimeSignatureNumerator) {
                        ForEach(timeSignatureNumerators, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 60)
                    .onChange(of: selectedTimeSignatureNumerator) { newValue in
                        metronome.timeSignatureNumerator = newValue
                    }

                    Text("/")

                    Picker("Denominator", selection: $selectedTimeSignatureDenominator) {
                        ForEach(timeSignatureDenominators, id: \.self) { den in
                            Text("\(den)").tag(den)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 60)
                    .onChange(of: selectedTimeSignatureDenominator) { newValue in
                        metronome.timeSignatureDenominator = newValue
                    }
                }

                Spacer()

                // Key Control
                Picker("Key", selection: $selectedKeyIndex) {
                    ForEach(0..<keys.count, id: \.self) { index in
                        Text(keys[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)

                Spacer()

                // Metronome Toggle
                Button(action: {
                    isMetronomePlaying.toggle()
                    if isMetronomePlaying {
                        metronome.start()
                    } else {
                        metronome.stop()
                    }
                }) {
                    Label(isMetronomePlaying ? "Stop Metronome" : "Start Metronome", systemImage: isMetronomePlaying ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Drum Machine Toggle
                Button(action: {
                    isDrumPlaying.toggle()
                    if isDrumPlaying {
                        // Pass current tempo and time signature from metronome to DrumPlayer
                        let timeSig = "\(selectedTimeSignatureNumerator)/\(selectedTimeSignatureDenominator)"
                        // Use JS drum defaults: velocity 100 and duration 200ms for note-off
                        drumPlayer.playPattern(patternName: "ROCK_4_4_BASIC", tempo: selectedTempo, timeSignature: timeSig, velocity: 100, durationMs: 200)
                    } else {
                        drumPlayer.stop()
                    }
                }) {
                    Label(isDrumPlaying ? "Stop Drums" : "Start Drums", systemImage: isDrumPlaying ? "beats.headphones.fill" : "beats.headphones")
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
}
