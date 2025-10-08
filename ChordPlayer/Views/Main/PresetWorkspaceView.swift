
import SwiftUI
import AppKit

struct PresetWorkspaceView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var keyboardHandler: KeyboardHandler
    @EnvironmentObject var chordPlayer: PresetArrangerPlayer
    @State private var segmentToEdit: SoloSegment?
    @State private var lyricSegmentToEdit: MelodicLyricSegment?
    @State private var activeMelodicLyricSegmentId: UUID?
    @State private var isPlayingKaraoke = false
    @State private var playheadPosition: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox {
                GlobalSettingsView(isPlayingKaraoke: $isPlayingKaraoke, playheadPosition: $playheadPosition)
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
                            SoloSegmentsView(segmentToEdit: $segmentToEdit)
                        }
                        GroupBox {
                            AccompanimentSegmentsView()
                        }
                        GroupBox {
                            MelodicLyricSegmentsView(segmentToEdit: $lyricSegmentToEdit, activeMelodicLyricSegmentId: $activeMelodicLyricSegmentId)
                        }
                        // MARK: - Song Arrangement Section
                        if let presetBinding = Binding($appData.preset) {
                            GroupBox {
                                ArrangementView(arrangement: presetBinding.arrangement, preset: presetBinding, playheadPosition: $playheadPosition)
                            }
                            .onReceive(chordPlayer.$playbackPosition) { newPosition in
                                playheadPosition = newPosition
                            }
                            .onChange(of: appData.preset?.arrangement) {
                                updateArrangementLength()
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
            } else {
                Text("Error: Could not find segment to edit.")
            }
        }
    }
    
    private func updateArrangementLength() {
        guard let preset = appData.preset else { return }
        
        var maxEndBeat: Double = 4.0 // Minimum length
        
        // Find the max end beat for drum segments
        if let lastDrumSegment = preset.arrangement.drumTrack.segments.max(by: { $0.startBeat + $0.durationInBeats < $1.startBeat + $1.durationInBeats }) {
            maxEndBeat = max(maxEndBeat, lastDrumSegment.startBeat + lastDrumSegment.durationInBeats)
        }
        
        // Find the max end beat for guitar segments
        for track in preset.arrangement.guitarTracks {
            if let lastGuitarSegment = track.segments.max(by: { $0.startBeat + $0.durationInBeats < $1.startBeat + $1.durationInBeats }) {
                maxEndBeat = max(maxEndBeat, lastGuitarSegment.startBeat + lastGuitarSegment.durationInBeats)
            }
        }
        
        // Find the max end beat for lyrics segments
        for track in preset.arrangement.lyricsTracks {
            if let lastLyricsSegment = track.lyrics.max(by: { $0.startBeat + $0.durationInBeats < $1.startBeat + $1.durationInBeats }) {
                maxEndBeat = max(maxEndBeat, lastLyricsSegment.startBeat + lastLyricsSegment.durationInBeats)
            }
        }
        
        // Round up to the nearest measure
        let beatsPerMeasure = Double(preset.timeSignature.beatsPerMeasure)
        guard beatsPerMeasure > 0 else { return }
        
        let newLength = ceil(maxEndBeat / beatsPerMeasure) * beatsPerMeasure
        let finalLength = max(4.0, newLength) // Ensure it's at least 4 beats

        // Only update if the length has actually changed, to avoid unnecessary redraws and saves.
        if finalLength != preset.arrangement.lengthInBeats {
            appData.preset?.arrangement.lengthInBeats = finalLength
        }
    }
    

}
