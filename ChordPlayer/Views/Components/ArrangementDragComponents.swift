import SwiftUI
import UniformTypeIdentifiers

// MARK: - 拖拽数据结构
struct ArrangementDragData: Codable {
    let type: String // "drum", "solo", "accompaniment", "lyrics"
    let resourceId: UUID
    let name: String
    let defaultDuration: Double

    enum CodingKeys: CodingKey {
        case type, resourceId, name, defaultDuration
    }
}

extension ArrangementDragData: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: ArrangementDragData.self, contentType: .data)
    }
}

// MARK: - 片段重新定位拖拽数据
enum SegmentType: Codable {
    case drum
    case guitar
    case lyrics
}

struct SegmentDragData: Codable {
    let segmentId: UUID
    let segmentType: SegmentType
    let originalStartBeat: Double
    let durationInBeats: Double

    enum CodingKeys: CodingKey {
        case segmentId, segmentType, originalStartBeat, durationInBeats
    }
}

extension SegmentDragData: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(for: SegmentDragData.self, contentType: .text)
    }
}

// MARK: - 片段视图组件

struct DrumSegmentView: View {
    let segment: DrumSegment
    let isSelected: Bool
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat
    let onEditDuration: ((DrumSegment) -> Void)?
    let onDelete: ((DrumSegment) -> Void)?

    @EnvironmentObject var appData: AppData

    private var patternName: String {
        appData.getDrumPattern(for: segment.patternId)?.name ?? "Unknown"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange.opacity(isSelected ? 0.8 : 0.6))
                .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)

            Text(patternName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .lineLimit(1)
        }
        .frame(
            width: CGFloat(segment.durationInBeats) * beatWidth * zoomLevel,
            height: trackHeight - 4
        )
        .contextMenu {
            Button("Edit Duration") {
                onEditDuration?(segment)
            }
            .disabled(onEditDuration == nil)

            Button("Delete", role: .destructive) {
                onDelete?(segment)
            }
            .disabled(onDelete == nil)
        }
        .draggable(SegmentDragData(
            segmentId: segment.id,
            segmentType: .drum,
            originalStartBeat: segment.startBeat,
            durationInBeats: segment.durationInBeats
        ))
    }
}

struct GuitarSegmentView: View {
    let segment: GuitarSegment
    let isSelected: Bool
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat
    let onEditDuration: ((GuitarSegment) -> Void)?
    let onDelete: ((GuitarSegment) -> Void)?

    @EnvironmentObject var appData: AppData

    private var segmentInfo: (name: String, color: Color) {
        switch segment.type {
        case .solo(let id):
            let name = appData.getSoloSegment(for: id)?.name ?? "Unknown Solo"
            return (name, .blue)
        case .accompaniment(let id):
            let name = appData.getAccompanimentSegment(for: id)?.name ?? "Unknown Accompaniment"
            return (name, .green)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(segmentInfo.color.opacity(isSelected ? 0.8 : 0.6))
                .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(segmentInfo.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(segment.type.displayName)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(
            width: CGFloat(segment.durationInBeats) * beatWidth * zoomLevel,
            height: trackHeight - 4
        )
        .contextMenu {
            Button("Edit Duration") {
                onEditDuration?(segment)
            }
            .disabled(onEditDuration == nil)

            Button("Delete", role: .destructive) {
                onDelete?(segment)
            }
            .disabled(onDelete == nil)
        }
        .draggable(SegmentDragData(
            segmentId: segment.id,
            segmentType: .guitar,
            originalStartBeat: segment.startBeat,
            durationInBeats: segment.durationInBeats
        ))
    }
}

struct LyricsSegmentView: View {
    let segment: LyricsSegment
    let isSelected: Bool
    let beatWidth: CGFloat
    let trackHeight: CGFloat
    let zoomLevel: CGFloat
    let onEdit: ((LyricsSegment) -> Void)?
    let onDelete: ((LyricsSegment) -> Void)?

    private var displayText: String {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lyrics" : trimmed
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.purple.opacity(isSelected ? 0.75 : 0.55))
                .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)

            Text(displayText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .frame(
            width: CGFloat(segment.durationInBeats) * beatWidth * zoomLevel,
            height: trackHeight - 4
        )
        .contextMenu {
            if let onEdit = onEdit {
                Button("Edit Lyrics") {
                    onEdit(segment)
                }
            }

            if let onDelete = onDelete {
                Button("Delete", role: .destructive) {
                    onDelete(segment)
                }
            }
        }
        .draggable(SegmentDragData(
            segmentId: segment.id,
            segmentType: .lyrics,
            originalStartBeat: segment.startBeat,
            durationInBeats: segment.durationInBeats
        ))
    }
}

// MARK: - 资源按钮组件

struct DrumPatternResourceButton: View {
    let pattern: DrumPattern

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "hifispeaker.fill")
                .font(.title2)
                .foregroundColor(.orange)

            Text(pattern.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text("\(pattern.length) steps")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(width: 120, height: 80)
        .background(Material.thin)
        .cornerRadius(8)
        .draggable(ArrangementDragData(
            type: "drum",
            resourceId: pattern.id,
            name: pattern.name,
            defaultDuration: 4.0 // 默认4拍
        ))
    }
}

struct SoloResourceButton: View {
    let segment: SoloSegment

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundColor(.blue)

            Text(segment.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text("\(Int(segment.lengthInBeats)) beats")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(width: 120, height: 80)
        .background(Material.thin)
        .cornerRadius(8)
        .draggable(ArrangementDragData(
            type: "solo",
            resourceId: segment.id,
            name: segment.name,
            defaultDuration: segment.lengthInBeats
        ))
    }
}

struct AccompanimentResourceButton: View {
    let segment: AccompanimentSegment

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "guitars.fill")
                .font(.title2)
                .foregroundColor(.green)

            Text(segment.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text("\(segment.lengthInMeasures) measures")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(width: 120, height: 80)
        .background(Material.thin)
        .cornerRadius(8)
        .draggable(ArrangementDragData(
            type: "accompaniment",
            resourceId: segment.id,
            name: segment.name,
            defaultDuration: Double(segment.lengthInMeasures * 4) // 假设4/4拍
        ))
    }
}

struct LyricsResourceButton: View {
    let segment: MelodicLyricSegment
    let beatsPerMeasure: Int

    private var previewText: String {
        let combined = segment.items.map { $0.word }.joined()
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return segment.name
        }
        if trimmed.count > 18 {
            let index = trimmed.index(trimmed.startIndex, offsetBy: 18)
            return String(trimmed[..<index]) + "…"
        }
        return trimmed
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "text.quote")
                .font(.title2)
                .foregroundColor(.purple)

            Text(segment.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text(previewText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(width: 140, height: 90)
        .background(Material.thin)
        .cornerRadius(8)
        .draggable(ArrangementDragData(
            type: "lyrics",
            resourceId: segment.id,
            name: segment.name,
            defaultDuration: Double(max(1, segment.lengthInBars)) * Double(max(1, beatsPerMeasure))
        ))
    }
}

// MARK: - 拖拽处理器

struct DrumTrackDropDelegate: DropDelegate {
    let track: DrumTrack
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let zoomLevel: CGFloat

    @EnvironmentObject var appData: AppData

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.data]) || info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        // Visual feedback could be added here
    }

    func dropExited(info: DropInfo) {
        // Visual feedback could be added here
    }

    func performDrop(info: DropInfo) -> Bool {
        let items = info.itemProviders(for: [.data])
        guard let provider = items.first else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
            guard let data = data,
                  let dragData = try? JSONDecoder().decode(ArrangementDragData.self, from: data),
                  dragData.type == "drum" else { return }

            DispatchQueue.main.async {
                let dropLocationX = info.location.x - 120 // 减去轨道控制区域宽度
                let beat = dropLocationX / (beatWidth * zoomLevel)
                let snappedBeat = max(0, floor(beat))

                let newSegment = DrumSegment(
                    startBeat: snappedBeat,
                    durationInBeats: dragData.defaultDuration,
                    patternId: dragData.resourceId
                )

                self.updateDrumTrack(with: newSegment)
            }
        }

        return true
    }

    private func updateDrumTrack(with segment: DrumSegment) {
        guard var preset = appData.preset else { return }
        preset.arrangement.drumTrack.addSegment(segment)
        appData.updateArrangement(preset.arrangement)
    }
}

struct GuitarTrackDropDelegate: DropDelegate {
    let track: GuitarTrack
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let zoomLevel: CGFloat

    @EnvironmentObject var appData: AppData

    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.data]) || info.hasItemsConforming(to: [.text])
    }

    func dropEntered(info: DropInfo) {
        // Visual feedback could be added here
    }

    func dropExited(info: DropInfo) {
        // Visual feedback could be added here
    }

    func performDrop(info: DropInfo) -> Bool {
        let items = info.itemProviders(for: [.data])
        guard let provider = items.first else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
            guard let data = data,
                  let dragData = try? JSONDecoder().decode(ArrangementDragData.self, from: data),
                  dragData.type == "solo" || dragData.type == "accompaniment" else { return }

            DispatchQueue.main.async {
                let dropLocationX = info.location.x - 120 // 减去轨道控制区域宽度
                let beat = dropLocationX / (beatWidth * zoomLevel)
                let snappedBeat = max(0, floor(beat))

                let segmentType: GuitarSegmentType = dragData.type == "solo"
                    ? .solo(segmentId: dragData.resourceId)
                    : .accompaniment(segmentId: dragData.resourceId)

                let newSegment = GuitarSegment(
                    startBeat: snappedBeat,
                    durationInBeats: dragData.defaultDuration,
                    type: segmentType
                )

                self.updateGuitarTrack(with: newSegment)
            }
        }

        return true
    }

    private func updateGuitarTrack(with segment: GuitarSegment) {
        guard var preset = appData.preset else { return }

        // 找到对应的轨道并添加片段
        if let trackIndex = preset.arrangement.guitarTracks.firstIndex(where: { $0.id == track.id }) {
            preset.arrangement.guitarTracks[trackIndex].addSegment(segment)
            appData.updateArrangement(preset.arrangement)
        }
    }
}

// MARK: - Enhanced Drop Delegates with Visual Feedback

struct EnhancedDrumTrackDropDelegate: DropDelegate {
    let track: DrumTrack
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let zoomLevel: CGFloat
    @Binding var isDragOver: Bool
    let appData: AppData

    func dropEntered(info: DropInfo) {
        isDragOver = true
    }

    func dropExited(info: DropInfo) {
        isDragOver = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDragOver = false

        guard let provider = info.itemProviders(for: [UTType.text, UTType.data]).first else {
            return false
        }

        let beatsPerMeasure = Double(self.appData.preset?.timeSignature.beatsPerMeasure ?? 4)

        // 优先尝试作为“重新定位”操作处理
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, error in
                guard let data = data,
                      let segmentDragData = try? JSONDecoder().decode(SegmentDragData.self, from: data),
                      segmentDragData.segmentType == .drum else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))
                    self.repositionDrumSegment(segmentId: segmentDragData.segmentId, newStartBeat: snappedBeat, appData: self.appData)
                }
            }
            return true
        }

        // 如果不是，则尝试作为“添加新片段”操作处理
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
                guard let data = data,
                      let dragData = try? JSONDecoder().decode(ArrangementDragData.self, from: data),
                      dragData.type == "drum" else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))
                    let newSegment = DrumSegment(startBeat: snappedBeat, durationInBeats: dragData.defaultDuration, patternId: dragData.resourceId)
                    self.updateDrumTrack(with: newSegment, appData: self.appData)
                }
            }
            return true
        }

        return false
    }

    private func updateDrumTrack(with segment: DrumSegment, appData: AppData) {
        guard var preset = appData.preset else { return }
        preset.arrangement.drumTrack.addSegment(segment)
        appData.updateArrangement(preset.arrangement)
    }

    private func repositionDrumSegment(segmentId: UUID, newStartBeat: Double, appData: AppData) {
        guard var preset = appData.preset else { return }
        var arrangement = preset.arrangement

        if let index = arrangement.drumTrack.segments.firstIndex(where: { $0.id == segmentId }) {
            arrangement.drumTrack.segments[index].startBeat = newStartBeat
            appData.updateArrangement(arrangement)
        }
    }
}

struct EnhancedGuitarTrackDropDelegate: DropDelegate {
    let track: GuitarTrack
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let zoomLevel: CGFloat
    @Binding var isDragOver: Bool
    let appData: AppData

    func dropEntered(info: DropInfo) {
        isDragOver = true
    }

    func dropExited(info: DropInfo) {
        isDragOver = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDragOver = false

        guard let provider = info.itemProviders(for: [UTType.text, UTType.data]).first else {
            return false
        }

        let beatsPerMeasure = Double(self.appData.preset?.timeSignature.beatsPerMeasure ?? 4)

        // 优先尝试作为“重新定位”操作处理
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, error in
                guard let data = data, let segmentDragData = try? JSONDecoder().decode(SegmentDragData.self, from: data) else { return }
                guard segmentDragData.segmentType == .guitar else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))
                    self.repositionGuitarSegment(segmentId: segmentDragData.segmentId, newStartBeat: snappedBeat, appData: self.appData)
                }
            }
            return true
        }

        // 如果不是，则尝试作为“添加新片段”操作处理
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, error in
                guard let data = data, let dragData = try? JSONDecoder().decode(ArrangementDragData.self, from: data) else { return }
                guard dragData.type == "solo" || dragData.type == "accompaniment" else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))
                    let segmentType: GuitarSegmentType = dragData.type == "solo" ? .solo(segmentId: dragData.resourceId) : .accompaniment(segmentId: dragData.resourceId)
                    let newSegment = GuitarSegment(startBeat: snappedBeat, durationInBeats: dragData.defaultDuration, type: segmentType)
                    self.updateGuitarTrack(with: newSegment, appData: self.appData)
                }
            }
            return true
        }

        return false
    }

    private func updateGuitarTrack(with segment: GuitarSegment, appData: AppData) {
        guard var preset = appData.preset else { return }

        if let trackIndex = preset.arrangement.guitarTracks.firstIndex(where: { $0.id == track.id }) {
            preset.arrangement.guitarTracks[trackIndex].addSegment(segment)
            appData.updateArrangement(preset.arrangement)
        }
    }

    private func repositionGuitarSegment(segmentId: UUID, newStartBeat: Double, appData: AppData) {
        guard var preset = appData.preset else {
            return
        }
        var arrangement = preset.arrangement
        var segmentToMove: GuitarSegment?
        
        for i in 0..<arrangement.guitarTracks.count {
            if let j = arrangement.guitarTracks[i].segments.firstIndex(where: { $0.id == segmentId }) {
                segmentToMove = arrangement.guitarTracks[i].segments.remove(at: j)
                break
            }
        }
        
        if var segment = segmentToMove {
            segment.startBeat = newStartBeat
            
            if let targetTrackIndex = arrangement.guitarTracks.firstIndex(where: { $0.id == self.track.id }) {
                arrangement.guitarTracks[targetTrackIndex].segments.append(segment)
                appData.updateArrangement(arrangement)
            }
        }
    }
}

struct EnhancedLyricsTrackDropDelegate: DropDelegate {
    let track: LyricsTrack
    let arrangement: SongArrangement
    let beatWidth: CGFloat
    let zoomLevel: CGFloat
    @Binding var isDragOver: Bool
    let appData: AppData

    func dropEntered(info: DropInfo) {
        isDragOver = true
    }

    func dropExited(info: DropInfo) {
        isDragOver = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDragOver = false

        guard let provider = info.itemProviders(for: [UTType.text, UTType.data]).first else {
            return false
        }

        let beatsPerMeasure = Double(appData.preset?.timeSignature.beatsPerMeasure ?? 4)

        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
                guard let data = data,
                      let segmentDragData = try? JSONDecoder().decode(SegmentDragData.self, from: data),
                      segmentDragData.segmentType == .lyrics else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))
                    self.repositionLyricsSegment(segmentId: segmentDragData.segmentId, newStartBeat: snappedBeat, appData: self.appData)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                guard let data = data,
                      let dragData = try? JSONDecoder().decode(ArrangementDragData.self, from: data),
                      dragData.type == "lyrics" else { return }

                DispatchQueue.main.async {
                    let beat = info.location.x / (beatWidth * zoomLevel)
                    let snappedBeat = max(0, floor(beat))

                    guard let melodicSegment = self.appData.getMelodicLyricSegment(for: dragData.resourceId) else { return }

                    let durationBeats = Double(max(1, melodicSegment.lengthInBars)) * beatsPerMeasure
                    let text = self.makeLyricText(from: melodicSegment)
                    let language = track.lyrics.first?.language ?? "zh"
                    let newSegment = LyricsSegment(
                        startBeat: snappedBeat,
                        durationInBeats: durationBeats,
                        text: text,
                        language: language
                    )
                    self.updateLyricsTrack(with: newSegment, appData: self.appData)
                }
            }
            return true
        }

        return false
    }

    private func makeLyricText(from segment: MelodicLyricSegment) -> String {
        let combined = segment.items.map { $0.word }.joined()
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? segment.name : trimmed
    }

    private func updateLyricsTrack(with segment: LyricsSegment, appData: AppData) {
        guard var preset = appData.preset else { return }
        if let trackIndex = preset.arrangement.lyricsTracks.firstIndex(where: { $0.id == self.track.id }) {
            preset.arrangement.lyricsTracks[trackIndex].addLyrics(segment)
            appData.updateArrangement(preset.arrangement)
        }
    }

    private func repositionLyricsSegment(segmentId: UUID, newStartBeat: Double, appData: AppData) {
        guard var preset = appData.preset else { return }
        var arrangement = preset.arrangement
        var segmentToMove: LyricsSegment?

        // Find and remove the segment from its original track
        for i in 0..<arrangement.lyricsTracks.count {
            if let j = arrangement.lyricsTracks[i].lyrics.firstIndex(where: { $0.id == segmentId }) {
                segmentToMove = arrangement.lyricsTracks[i].lyrics.remove(at: j)
                break
            }
        }

        if var segment = segmentToMove {
            segment.startBeat = newStartBeat
            
            // Add the segment to the new target track
            if let targetTrackIndex = arrangement.lyricsTracks.firstIndex(where: { $0.id == self.track.id }) {
                arrangement.lyricsTracks[targetTrackIndex].lyrics.append(segment)
                arrangement.lyricsTracks[targetTrackIndex].lyrics.sort { $0.startBeat < $1.startBeat }
                appData.updateArrangement(arrangement)
            }
        }
    }
}
