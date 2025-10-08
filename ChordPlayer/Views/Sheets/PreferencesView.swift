import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var midiManager: MidiManager

    var body: some View {
        Form {
            Section(header: Text("Global Settings")) {
                LabeledContent {
                    Picker("MIDI Output Port", selection: $appData.midiPortName) {
                        ForEach(midiManager.availableOutputs, id: \.self) { endpoint in
                            Text(midiManager.displayName(for: endpoint)).tag(midiManager.displayName(for: endpoint))
                        }
                    }
                    .labelsHidden()
                } label: {
                    Label("MIDI Output", systemImage: "pianokeys.inverse")
                }
            }
            
            Section(header: Text("Karaoke Font Settings")) {
                LabeledContent {
                    Slider(value: $appData.karaokePrimaryLineFontSize, in: 20...80, step: 1)
                    Text("\(Int(appData.karaokePrimaryLineFontSize)) pt").frame(width: 50, alignment: .leading)
                } label: {
                    Label("Primary Line", systemImage: "textformat.size.larger")
                }
                
                LabeledContent {
                    Slider(value: $appData.karaokeSecondaryLineFontSize, in: 14...60, step: 1)
                    Text("\(Int(appData.karaokeSecondaryLineFontSize)) pt").frame(width: 50, alignment: .leading)
                } label: {
                    Label("Secondary Line", systemImage: "textformat.size")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live Preview").font(.caption).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: appData.karaokePrimaryLineFontSize / 2) {
                        Text("This is the primary line for lyrics.")
                            .font(.system(size: appData.karaokePrimaryLineFontSize, design: .monospaced).weight(.bold))
                            .foregroundColor(.white)
                        
                        Text("This is the secondary, upcoming line.")
                            .font(.system(size: appData.karaokeSecondaryLineFontSize, design: .monospaced).weight(.bold))
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 380)
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
