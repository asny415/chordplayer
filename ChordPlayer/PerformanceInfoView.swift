
import SwiftUI

struct PerformanceInfoView: View {
    @EnvironmentObject var appData: AppData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("演奏信息").font(.headline)
                Spacer()
            }

            HStack {
                Text("时间:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(appData.currentMeasure)小节, \(appData.currentBeat)拍")
                    .font(.body)
            }

            HStack {
                Text("和弦:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(appData.currentlyPlayingChordName ?? "N/A")
                    .font(.body)
            }

            HStack {
                Text("指法:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(appData.currentlyPlayingPatternName ?? "N/A")
                    .font(.body)
            }
            
            Spacer()
        }
    }
}

struct PerformanceInfoView_Previews: PreviewProvider {
    static var previews: some View {
        PerformanceInfoView()
            .environmentObject(AppData())
    }
}
