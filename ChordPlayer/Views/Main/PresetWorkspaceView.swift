
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler

    var body: some View {
        ZStack {
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
            .blur(radius: appData.showShortcutDialog ? 3 : 0)
            .allowsHitTesting(!appData.showShortcutDialog)
            
            // 全局快捷键设置对话框
            if appData.showShortcutDialog {
                GlobalShortcutDialogView()
                    .environmentObject(appData)
                    .environmentObject(keyboardHandler)
            }
        }
    }
}
