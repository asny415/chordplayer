
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var segmentToEdit: SoloSegment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 歌曲编排功能 - 基于Preset
                GroupBox {
                    PresetArrangementView()
                }

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
                    SoloSegmentsView(segmentToEdit: $segmentToEdit)
                }

                GroupBox {
                    AccompanimentSegmentsView()
                }

            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .sheet(item: $segmentToEdit) { segment in
            if let index = appData.preset?.soloSegments.firstIndex(where: { $0.id == segment.id }) {
                let segmentBinding = Binding<SoloSegment>(
                    get: { appData.preset!.soloSegments[index] },
                    set: { appData.preset!.soloSegments[index] = $0 }
                )
                
                NavigationStack {
                    SoloEditorView(soloSegment: segmentBinding)
                        .navigationTitle("Edit: \(segment.name)")
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Done") {
                                    appData.saveChanges()
                                    segmentToEdit = nil
                                }
                            }
                        }
                }
                .frame(minWidth: 800, minHeight: 600)
            } else {
                Text("Error: Could not find segment to edit.")
            }
        }
    }
}
