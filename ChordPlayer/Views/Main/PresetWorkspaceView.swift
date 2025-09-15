
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {                
                GroupBox {
                    GlobalSettingsView()
                }
                
                GroupBox {
                    DrumPatternsView()
                }

                GroupBox {
                    PlayingPatternsView()
                }

                GroupBox {
                    ChordProgressionView()
                }

                
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
