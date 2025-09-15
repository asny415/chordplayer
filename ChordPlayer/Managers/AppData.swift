import Foundation
import Combine
import AppKit

class AppData: ObservableObject {
    // The single source of truth for the currently active preset's data.
    @Published var preset: Preset?

    // UI and playback state
    @Published var currentBeatInfo: (beat: Int, measure: Int, timestamp: Double) = (-4, 0, 0)
    @Published var currentlyPlayingChordName: String? = nil
    @Published var playingMode: PlayingMode = .manual

    private let presetManager = PresetManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to the PresetManager's currentPreset
        presetManager.$currentPreset
            .assign(to: &$preset)
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
    
    func updateChordProgression(_ newProgression: [String]) {
        preset?.chordProgression = newProgression
        saveChanges()
    }
}
