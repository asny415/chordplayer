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

struct ChordButtonView: View {
    let chordName: String
    let isSelected: Bool
    let shortcut: String?
    let action: () -> Void
    
    private var displayName: (String, String) {
        if chordName.hasSuffix("_Major") {
            let root = chordName.replacingOccurrences(of: "_Major", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Major")
        }
        if chordName.hasSuffix("_Minor") {
            let root = chordName.replacingOccurrences(of: "_Minor", with: "")
                .replacingOccurrences(of: "_Sharp", with: "#")
                .replacingOccurrences(of: "_", with: "")
            return (root, "Minor")
        }
        
        var label = chordName.replacingOccurrences(of: "_Sharp", with: "#")
        label = label.replacingOccurrences(of: "_", with: " ")
        return (label, "")
    }
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Main content
                VStack {
                    Text(displayName.0)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .primary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    if !displayName.1.isEmpty {
                        Text(displayName.1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Shortcut key overlay
                if let shortcut = shortcut {
                    Text(shortcut.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(5)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .frame(minWidth: 100, minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.2), radius: isSelected ? 8 : 3, x: 0, y: isSelected ? 4 : 1)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }
}


// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    let keys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    var body: some View {
        ZStack {
            // Main background color
            Color.black.opacity(0.9).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Top Control Bar
                controlBar
                    .padding()
                    .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // MARK: - Chord Buttons
                chordGrid
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600) // Increased minWidth for more horizontal space
        .onAppear(perform: setupInitialState)
    }
    
    // MARK: - Control Bar View
    private var controlBar: some View {
        HStack(spacing: 16) {
            // MIDI Output
            StyledPicker(
                title: "MIDI Output",
                selection: $midiManager.selectedOutput,
                items: [nil] + midiManager.availableOutputs,
                display: { endpoint in
                    endpoint.map { midiManager.displayName(for: $0) } ?? "None"
                }
            ).frame(width: 160)
            
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
            .buttonStyle(.plain)
            .focusable(false)
        }
        .focusable(false)
    }
    
    // MARK: - Chord Grid View
    private var chordGrid: some View {
        ScrollView {
            if let chordLibrary = appData.chordLibrary {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 20) {
                    ForEach(chordLibrary.keys.sorted(), id: \.self) { chordName in
                        ChordButtonView(
                            chordName: chordName,
                            isSelected: keyboardHandler.activeChordName == chordName,
                            shortcut: MusicTheory.defaultChordToShortcutMap[chordName],
                            action: {
                                keyboardHandler.playChordButton(chordName: chordName)
                            }
                        )
                    }
                }
                .padding()
            } else {
                Text("Loading chords...")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        }
        .focusable(false)
    }
    
    // MARK: - Setup
    private func setupInitialState() {
        DispatchQueue.main.async {
            keyboardHandler.currentTimeSignature = appData.performanceConfig.timeSignature
            keyboardHandler.currentTempo = appData.performanceConfig.tempo
            
            let parts = appData.performanceConfig.timeSignature.split(separator: "/").map(String.init)
            if parts.count == 2, let num = Int(parts[0]), let den = Int(parts[1]) {
                metronome.timeSignatureNumerator = num
                metronome.timeSignatureDenominator = den
            }
            metronome.tempo = appData.performanceConfig.tempo
        }
    }
}

// MARK: - Preview
#Preview {
    // Creating a more robust preview environment
    let midiManager = MidiManager()
    let metronome = Metronome(midiManager: midiManager)
    let appData = AppData()
    let guitarPlayer = GuitarPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
    let drumPlayer = DrumPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
    let keyboardHandler = KeyboardHandler(midiManager: midiManager, metronome: metronome, guitarPlayer: guitarPlayer, drumPlayer: drumPlayer, appData: appData)
    
    ContentView()
        .environmentObject(appData)
        .environmentObject(midiManager)
        .environmentObject(metronome)
        .environmentObject(guitarPlayer)
        .environmentObject(drumPlayer)
        .environmentObject(keyboardHandler)
}
