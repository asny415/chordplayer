
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var escapeMonitor: Any? = nil

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

                    

                    if appData.playingMode == .assisted || appData.playingMode == .automatic {
                        GroupBox {
                            TimingDisplayView()
                        }
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
        .onAppear {
            setupEscapeKeyMonitoring()
        }
        .onDisappear {
            cleanupEscapeKeyMonitoring()
        }
    }
    
    private func setupEscapeKeyMonitoring() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                if appData.sheetMusicEditingBeat != nil {
                    // 取消曲谱编辑
                    appData.sheetMusicEditingBeat = nil
                    appData.sheetMusicSelectedChordName = nil
                    appData.sheetMusicSelectedPatternId = nil
                    return nil // 消费该事件，不让其传播
                }
            }
            return event // 其他情况下让事件继续传播
        }
    }
    
    private func cleanupEscapeKeyMonitoring() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }
}
