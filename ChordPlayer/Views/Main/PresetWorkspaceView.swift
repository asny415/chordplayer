
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @StateObject private var soloEditorManager = SoloEditorWindowManager()

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
                    ChordProgressionView()
                }

                GroupBox {
                    PlayingPatternsView()
                }
                
                GroupBox {
                    SoloSegmentsView(soloEditorManager: soloEditorManager)
                }
                
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .environmentObject(soloEditorManager)
        .onAppear {
            soloEditorManager.setAppData(appData)
        }
    }
}
