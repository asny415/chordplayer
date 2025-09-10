
import SwiftUI

struct PerformanceInfoView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("演奏信息").font(.headline)
                Spacer()
                Text("\(appData.currentMeasure)小节, \(appData.currentBeat)拍")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let info = keyboardHandler.currentPlayingInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前和弦")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(info.chordName.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }
                }
            } else {
                Text("未演奏")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Divider()

            if let nextInfo = keyboardHandler.nextPlayingInfo, let beats = keyboardHandler.beatsToNextChord {
                VStack(alignment: .leading, spacing: 8) {
                    Text("下一个和弦")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(nextInfo.chordName.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        
                        Text(nextInfo.shortcut)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .padding(5)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: keyboardHandler.currentChordProgress)
                            .progressViewStyle(.linear)
                            .frame(height: 4)
                        Text("剩余 \(beats) 拍")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text("-")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PerformanceInfoView_Previews: PreviewProvider {
    static var previews: some View {
        let appData = AppData()
        let midiManager = MidiManager()
        let chordPlayer = ChordPlayer(midiManager: midiManager, appData: appData)
        let drumPlayer = DrumPlayer(midiManager: midiManager, appData: appData)
        let keyboardHandler = KeyboardHandler(midiManager: midiManager, chordPlayer: chordPlayer, drumPlayer: drumPlayer, appData: appData)
        
        // Sample data for preview
        keyboardHandler.currentPlayingInfo = PlayingInfo(chordName: "C_Major", shortcut: "C", duration: 4)
        keyboardHandler.nextPlayingInfo = PlayingInfo(chordName: "G_Major", shortcut: "G", duration: 4)
        keyboardHandler.beatsToNextChord = 3
        keyboardHandler.currentChordProgress = 0.25
        appData.currentMeasure = 1
        appData.currentBeat = 2

        return PerformanceInfoView()
            .environmentObject(appData)
            .environmentObject(keyboardHandler)
            .frame(width: 250, height: 300)
            .padding()
    }
}
