import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager

    var body: some View {
        Form {
            Section(header: Text("MIDI Settings")) {
                Picker("MIDI Output Port", selection: $appData.midiPortName) {
                    ForEach(midiManager.availableOutputs, id: \.self) { endpoint in
                        Text(midiManager.displayName(for: endpoint)).tag(midiManager.displayName(for: endpoint))
                    }
                }
                
                Picker("Chord MIDI Channel", selection: $appData.chordMidiChannel) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("Channel \(channel)").tag(channel)
                    }
                }
                
                Picker("Drum MIDI Channel", selection: $appData.drumMidiChannel) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("Channel \(channel)").tag(channel)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        let midiManager = MidiManager()
        let appData = AppData(midiManager: midiManager)
        PreferencesView()
            .environmentObject(appData)
            .environmentObject(midiManager)
    }
}
