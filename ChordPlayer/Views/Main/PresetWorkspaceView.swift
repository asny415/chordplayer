
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @State private var segmentToEdit: SoloSegment?
    @State private var lyricSegmentToEdit: MelodicLyricSegment?
    @State private var isPlayingKaraoke = false
    @State private var playheadPosition: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                GlobalSettingsView(isPlayingKaraoke: $isPlayingKaraoke)
            }
            .padding(.horizontal)
            .padding(.top)

            if isPlayingKaraoke {
                KaraokeView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                        GroupBox {
                            MelodicLyricSegmentsView(segmentToEdit: $lyricSegmentToEdit)
                        }
                        // MARK: - Song Arrangement Section
                        if let presetBinding = Binding($appData.preset) {
                            GroupBox {
                                ArrangementView(arrangement: presetBinding.arrangement, preset: presetBinding, playheadPosition: $playheadPosition)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isPlayingKaraoke)
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
        .sheet(item: $lyricSegmentToEdit, onDismiss: {
            appData.saveChanges()
        }) { segment in
            if let index = appData.preset?.melodicLyricSegments.firstIndex(where: { $0.id == segment.id }) {
                let segmentBinding = Binding<MelodicLyricSegment>(
                    get: { appData.preset!.melodicLyricSegments[index] },
                    set: { appData.preset!.melodicLyricSegments[index] = $0 }
                )
                
                NavigationStack {
                    MelodicLyricEditorView(segment: segmentBinding)
                        .navigationTitle("Edit: \(segment.name)")
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Done") {
                                    lyricSegmentToEdit = nil
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
