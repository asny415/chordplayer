
import SwiftUI

struct ArrangementView: View {
    @EnvironmentObject var appData: AppData
    @Binding var arrangement: SongArrangement
    @Binding var preset: Preset
    @Binding var playheadPosition: Double

    // The base width for one beat, to be multiplied by the scale factor.
    private let basePixelsPerBeat: CGFloat = 30.0
    
    // Computed property for dynamic pixels per beat based on the zoom scale
    private var pixelsPerBeat: CGFloat {
        basePixelsPerBeat * appData.currentTimelineScale
    }
    
    // State for the slider's value to enable snapping behavior
    @State private var sliderValue: Double = 0.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Header for the arrangement section
                HStack {
                    Text("歌曲编排 (Arrangement)")
                        .font(.headline)
                    Spacer()
                    
                    // Add guitar track or lyrics track dropdown
                    Menu {
                        Button(action: {
                            arrangement.addGuitarTrack()
                        }) {
                            Label("添加吉他轨道", systemImage: "guitars.fill")
                        }
                        
                        Button(action: {
                            arrangement.addLyricsTrack()
                        }) {
                            Label("添加歌词轨道", systemImage: "text.quote")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("添加吉他轨道或歌词轨道")
                }
                .padding(.bottom, 5)

                // A single ScrollView for the ruler and all tracks to ensure synchronized scrolling
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        // Calculate the total width of the timeline content outside the VStack
                        let totalWidth = max(1200, pixelsPerBeat * arrangement.lengthInBeats)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // "Anchor Rail" - A static, invisible rail of all possible beat anchors
                            HStack(spacing: 0) {
                                ForEach(0..<Int(arrangement.lengthInBeats), id: \.self) { beat in
                                    Rectangle()
                                        .fill(Color.clear) // Invisible
                                        .frame(width: pixelsPerBeat, height: 1)
                                        .id("beat_\(beat)")
                                }
                            }
                            .frame(height: 1)
                            .padding(.leading, 120) // Align with timeline content

                            // 1. The real Timeline Ruler, wrapped in an HStack to align with track headers
                            HStack(spacing: 0) {
                                // Spacer to align with track headers
                                Rectangle().fill(Color.clear).frame(width: 120)
                                
                                TimelineRulerView(
                                    playheadPosition: $playheadPosition,
                                    lengthInBeats: arrangement.lengthInBeats,
                                    timeSignature: preset.timeSignature,
                                    pixelsPerBeat: pixelsPerBeat
                                )
                            }
                            .frame(height: 24)

                            // 2. The Tracks
                            if (preset.drumPatterns.isEmpty == false) || appData.showDrumPatternSectionByDefault {
                                DrumTrackView(
                                    track: $arrangement.drumTrack,
                                    preset: $preset,
                                    pixelsPerBeat: pixelsPerBeat,
                                    onRemove: removeDrumSegment
                                )
                            }

                            ForEach($arrangement.guitarTracks) { $track in
                                GuitarTrackView(
                                    track: $track,
                                    preset: $preset,
                                    pixelsPerBeat: pixelsPerBeat,
                                    onRemove: { segmentId in
                                        removeGuitarSegment(segmentId: segmentId, from: track.id)
                                    },
                                    onRemoveTrack: { trackId in
                                        removeGuitarTrack(trackId: trackId)
                                    }
                                )
                            }

                            ForEach($arrangement.lyricsTracks) { $track in
                                LyricsTrackView(
                                    track: $track,
                                    preset: $preset,
                                    pixelsPerBeat: pixelsPerBeat,
                                    onRemove: { segmentId in
                                        removeLyricsSegment(segmentId: segmentId, from: track.id)
                                    },
                                    onRemoveTrack: { trackId in
                                        removeLyricsTrack(trackId: trackId)
                                    }
                                )
                            }
                        }
                        .padding(.top, 4)
                        // Apply the calculated total width to the VStack containing all timeline content
                        .frame(minWidth: totalWidth + 120)
                        .overlay(
                            // GeometryReader to get the full height of the content for the playhead line
                            GeometryReader { geometry in
                                PlayheadView()
                                    .frame(height: geometry.size.height)
                                    .offset(x: 120 + (playheadPosition * pixelsPerBeat)) // 120 for track header width
                            }
                        )
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: playheadPosition) { _,newPosition in
                        let currentBeat = Int(newPosition)
                        let targetID = "beat_\(currentBeat)"
                        
                        // This handles both playback and seeking.
                        if newPosition >= 0 {
                            withAnimation(.easeIn(duration: 0.3)) {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                    }
                }
            }
            
            // Zoom Control UI
            HStack {
                Text("\(Int(appData.currentTimelineScale * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 50, alignment: .trailing)
                
                Slider(
                    value: $sliderValue,
                    in: 0...Double(appData.timelineScaleLevels.count - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing {
                            // Snap to the nearest integer index
                            let newIndex = Int(round(sliderValue))
                            appData.timelineScaleIndex = newIndex
                            // Ensure the slider visually snaps to the new index
                            sliderValue = Double(newIndex)
                        }
                    }
                )
                .frame(width: 150)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.4))
                    .shadow(radius: 5)
            )
            .padding()
            .onAppear {
                // Set the initial slider value from AppData when the view appears
                sliderValue = Double(appData.timelineScaleIndex)
            }
            .onChange(of: appData.timelineScaleIndex) {
                // Update slider value if the index changes from another source
                sliderValue = Double(appData.timelineScaleIndex)
            }
        }
    }
    
    // MARK: - Segment Removal Methods
    
    private func removeDrumSegment(segmentId: UUID) {
        arrangement.drumTrack.segments.removeAll { $0.id == segmentId }
        appData.saveChanges()
    }
    
    private func removeGuitarSegment(segmentId: UUID, from trackId: UUID) {
        if let trackIndex = arrangement.guitarTracks.firstIndex(where: { $0.id == trackId }) {
            arrangement.guitarTracks[trackIndex].removeSegment(withId: segmentId)
            appData.saveChanges()
        }
    }
    
    private func removeLyricsSegment(segmentId: UUID, from trackId: UUID) {
        if let trackIndex = arrangement.lyricsTracks.firstIndex(where: { $0.id == trackId }) {
            arrangement.lyricsTracks[trackIndex].removeLyrics(withId: segmentId)
            appData.saveChanges()
        }
    }
    
    private func removeGuitarTrack(trackId: UUID) {
        arrangement.guitarTracks.removeAll { $0.id == trackId }
        appData.saveChanges()
    }
    
    private func removeLyricsTrack(trackId: UUID) {
        arrangement.lyricsTracks.removeAll { $0.id == trackId }
        appData.saveChanges()
    }
}
