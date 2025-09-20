import Foundation
import Combine
import AppKit
import CoreMIDI

class AppData: ObservableObject {
    // The single source of truth for the currently active preset's data.
    @Published var preset: Preset?

    // UI and playback state
    @Published var currentBeatInfo: (beat: Int, measure: Int, timestamp: Double) = (-4, 0, 0)
    @Published var currentlyPlayingChordName: String? = nil
    @Published var playingMode: PlayingMode = .manual
    
    // Global MIDI Settings
    @Published var midiPortName: String
    @Published var chordMidiChannel: Int
    @Published var drumMidiChannel: Int

    private let presetManager = PresetManager.shared
    private var cancellables = Set<AnyCancellable>()

    init(midiManager: MidiManager) {
        // Load MIDI settings from UserDefaults or set defaults
        let defaultPortName = midiManager.availableOutputs.first.map { midiManager.displayName(for: $0) } ?? "None"
        
        self.midiPortName = UserDefaults.standard.string(forKey: "midiPortName") ?? defaultPortName
        self.chordMidiChannel = UserDefaults.standard.object(forKey: "chordMidiChannel") as? Int ?? 1
        self.drumMidiChannel = UserDefaults.standard.object(forKey: "drumMidiChannel") as? Int ?? 10

        // Subscribe to the PresetManager's currentPreset
        presetManager.$currentPreset
            .assign(to: &$preset)

        // Save MIDI settings to UserDefaults when they change
        $midiPortName
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { portName in
                UserDefaults.standard.set(portName, forKey: "midiPortName")
                // We also need to update the MidiManager's selected output
                if let newOutput = midiManager.availableOutputs.first(where: { midiManager.displayName(for: $0) == portName }) {
                    midiManager.selectedOutput = newOutput
                }
            }
            .store(in: &cancellables)

        $chordMidiChannel
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { channel in
                UserDefaults.standard.set(channel, forKey: "chordMidiChannel")
            }
            .store(in: &cancellables)

        $drumMidiChannel
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { channel in
                UserDefaults.standard.set(channel, forKey: "drumMidiChannel")
            }
            .store(in: &cancellables)
    }

    // MARK: - Preset Management
    
    func loadPreset(_ presetInfo: PresetInfo) {
        presetManager.loadPreset(presetInfo)
    }
    
    func createNewPreset(name: String) {
        _ = presetManager.createNewPreset(name: name)
    }
    
    func saveChanges() {
        guard let preset = preset else { return }
        presetManager.updateCurrentPreset(preset)
    }

    // MARK: - Data Modification Methods
    // These methods modify the local copy of the preset.
    // Call saveChanges() to persist them.

    func addChord(_ chord: Chord) {
        preset?.chords.append(chord)
        saveChanges()
    }

    func removeChord(at offsets: IndexSet) {
        preset?.chords.remove(atOffsets: offsets)
        saveChanges()
    }
    
    func addPlayingPattern(_ pattern: GuitarPattern) {
        preset?.playingPatterns.append(pattern)
        saveChanges()
    }

    func removePlayingPattern(at offsets: IndexSet) {
        preset?.playingPatterns.remove(atOffsets: offsets)
        saveChanges()
    }
    
    func addDrumPattern(_ pattern: DrumPattern) {
        preset?.drumPatterns.append(pattern)
        saveChanges()
    }

    func removeDrumPattern(at offsets: IndexSet) {
        preset?.drumPatterns.remove(atOffsets: offsets)
        saveChanges()
    }
    
    func addSoloSegment(_ segment: SoloSegment) {
        preset?.soloSegments.append(segment)
        saveChanges()
    }
    
    func removeSoloSegment(at offsets: IndexSet) {
        preset?.soloSegments.remove(atOffsets: offsets)
        saveChanges()
    }
    
    func updateSoloSegment(_ segment: SoloSegment) {
        guard let index = preset?.soloSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        preset?.soloSegments[index] = segment
        saveChanges()
    }

    // MARK: - Accompaniment Segment Management

    func addAccompanimentSegment(_ segment: AccompanimentSegment) {
        preset?.accompanimentSegments.append(segment)
        saveChanges()
    }

    func removeAccompanimentSegment(at offsets: IndexSet) {
        preset?.accompanimentSegments.remove(atOffsets: offsets)
        saveChanges()
    }

    func updateAccompanimentSegment(_ segment: AccompanimentSegment) {
        guard let index = preset?.accompanimentSegments.firstIndex(where: { $0.id == segment.id }) else { return }
        preset?.accompanimentSegments[index] = segment
        saveChanges()
    }

    func getChord(for id: UUID?) -> Chord? {
        guard let id = id else { return nil }
        return preset?.chords.first(where: { $0.id == id })
    }

    func getPlayingPattern(for id: UUID?) -> GuitarPattern? {
        guard let id = id else { return nil }
        return preset?.playingPatterns.first(where: { $0.id == id })
    }

    func updateChordProgression(_ newProgression: [String]) {
        preset?.chordProgression = newProgression
        saveChanges()
    }

    // MARK: - Song Arrangement Management

    func updateArrangement(_ arrangement: SongArrangement) {
        preset?.arrangement = arrangement
        saveChanges()
    }

    func addGuitarTrackToArrangement() {
        preset?.arrangement.addGuitarTrack()
        saveChanges()
    }

    func removeGuitarTrackFromArrangement(trackId: UUID) {
        preset?.arrangement.removeGuitarTrack(withId: trackId)
        saveChanges()
    }

    // MARK: - Arrangement Content Helpers

    func getDrumPattern(for id: UUID?) -> DrumPattern? {
        guard let id = id else { return nil }
        return preset?.drumPatterns.first(where: { $0.id == id })
    }

    func getSoloSegment(for id: UUID?) -> SoloSegment? {
        guard let id = id else { return nil }
        return preset?.soloSegments.first(where: { $0.id == id })
    }

    func getAccompanimentSegment(for id: UUID?) -> AccompanimentSegment? {
        guard let id = id else { return nil }
        return preset?.accompanimentSegments.first(where: { $0.id == id })
    }

    func getMelodicLyricSegment(for id: UUID?) -> MelodicLyricSegment? {
        guard let id = id else { return nil }
        let segment = preset?.melodicLyricSegments.first(where: { $0.id == id })
        print("[DEBUG] getMelodicLyricSegment for id \(id): \(segment != nil ? "Found" : "Not Found")")
        return segment
    }
}
