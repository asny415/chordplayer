
import SwiftUI

struct TimingDisplayWindowView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    var body: some View {
        TimingDisplayView()
            .environmentObject(appData)
            .environmentObject(keyboardHandler)
            .frame(minWidth: 400, minHeight: 120)
    }
}
