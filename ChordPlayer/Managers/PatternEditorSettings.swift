
import SwiftUI
import Combine

// GridResolution is RawRepresentable with a String raw value, so it's compatible with @AppStorage.

class PatternEditorSettings: ObservableObject {
    @AppStorage("defaultPatternResolution") var resolution: GridResolution = .sixteenth
    @AppStorage("defaultPatternBeats") var lengthInBeats: Int = 4
}
