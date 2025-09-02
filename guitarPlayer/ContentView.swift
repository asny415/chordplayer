import SwiftUI
import CoreMIDI

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager
    @EnvironmentObject var metronome: Metronome
    @EnvironmentObject var guitarPlayer: GuitarPlayer
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    
    var body: some View {
    ZStack {
            // Main background color
            Color.black.opacity(0.9).ignoresSafeArea()
            
                VStack(alignment: .leading, spacing: 10) {
                // MARK: - Top Control Bar
                ControlBarView()
                    .padding()
                    .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // MARK: - Group Configuration Panel
                GroupConfigPanelView()
                                .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600) // Increased minWidth for more horizontal space
        .onAppear(perform: setupInitialState)
        // Clicking on empty area should clear focus so global shortcuts work again
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.keyWindow?.makeFirstResponder(nil)
            keyboardHandler.isTextInputActive = false
        }
    }
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
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // Creating a more robust preview environment
        let midiManager = MidiManager()
        let metronome = Metronome(midiManager: midiManager)
        let appData = AppData()
        let guitarPlayer = GuitarPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
        let drumPlayer = DrumPlayer(midiManager: midiManager, metronome: metronome, appData: appData)
        let keyboardHandler = KeyboardHandler(midiManager: midiManager, metronome: metronome, guitarPlayer: guitarPlayer, drumPlayer: drumPlayer, appData: appData)

        return ContentView()
            .environmentObject(appData)
            .environmentObject(midiManager)
            .environmentObject(metronome)
            .environmentObject(guitarPlayer)
            .environmentObject(drumPlayer)
            .environmentObject(keyboardHandler)
    }
}