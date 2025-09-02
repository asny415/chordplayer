import Foundation
import Combine

class AppData: ObservableObject {
    @Published var chordLibrary: ChordLibrary?
    @Published var drumPatternLibrary: DrumPatternLibrary?
    @Published var patternLibrary: PatternLibrary?

    // Configuration properties
    var performanceConfig: PerformanceConfig
    let KEY_CYCLE: [String]
    let TIME_SIGNATURE_CYCLE: [String]
    let DRUM_PATTERN_MAP: [String: String]
    let CONFIG: AppConfig
    let DEFAULT_PATTERNS: [String: [String: [String: [String: String]]]] // Add this

    init() {
        // Initialize configuration properties with default values from JS files
            self.performanceConfig = PerformanceConfig(
            tempo: 120,
            timeSignature: "4/4",
            key: "C",
            quantize: QuantizationMode.measure.rawValue, // Use rawValue for enum
            quantizeToggleKey: "q",
            drumSettings: DrumSettings(playKey: "p", stopKey: "o", defaultPattern: "ROCK_4_4_BASIC"),
            keyMap: [:],
            patternGroups: [
                // Simplified group names for clarity; original intent: Intro/Arpeggio
                PatternGroup(name: "Intro", patterns: ["__default__": nil]),
                // Simplified group name; original intent: Verse/Picking
                PatternGroup(name: "Verse", patterns: ["__default__": nil]),
                // Simplified group name; original intent: Chorus/Strum
                PatternGroup(name: "Chorus", patterns: ["__default__": nil])
            ]
        )

        self.KEY_CYCLE = [
            "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
        ]
        self.TIME_SIGNATURE_CYCLE = ["4/4", "3/4", "6/8"]
        self.DRUM_PATTERN_MAP = [
            "4/4": "ROCK_4_4_BASIC",
            "3/4": "WALTZ_3_4_BASIC",
            "6/8": "SHUFFLE_6_8_BASIC",
        ]
        self.CONFIG = AppConfig(
            midiPortName: "IAC驱动程序 总线1",
            note: 60,
            velocity: 64,
            duration: 4000,
            channel: 0
        )

        // Initialize DEFAULT_PATTERNS
        self.DEFAULT_PATTERNS = [
            "Major": [
                "4/4": [
                    "intro": [
                        "6th_string": "INTRO_ARPEGGIO_4_4_6TH_ROOT",
                        "5th_string": "INTRO_ARPEGGIO_4_4_5TH_ROOT",
                        "4th_string": "INTRO_ARPEGGIO_4_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "VERSE_PICKING_4_4_6TH_ROOT",
                        "5th_string": "VERSE_PICKING_4_4_5TH_ROOT",
                        "4th_string": "VERSE_PICKING_4_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "CHORUS_STRUM_4_4_6TH_ROOT",
                        "5th_string": "CHORUS_STRUM_4_4_5TH_ROOT",
                        "4th_string": "CHORUS_STRUM_4_4_4TH_ROOT",
                    ],
                ],
                "3/4": [
                    "intro": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "WALTZ_CHORUS_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_CHORUS_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_CHORUS_3_4_4TH_ROOT",
                    ],
                ],
                "6/8": [
                    "intro": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "FOLK_CHORUS_6_8_6TH_ROOT",
                        "5th_string": "FOLK_CHORUS_6_8_5TH_ROOT",
                        "4th_string": "FOLK_CHORUS_6_8_4TH_ROOT",
                    ],
                ],
            ],
            "Minor": [
                "4/4": [
                    "intro": [
                        "6th_string": "INTRO_ARPEGGIO_4_4_6TH_ROOT",
                        "5th_string": "INTRO_ARPEGGIO_4_4_5TH_ROOT",
                        "4th_string": "INTRO_ARPEGGIO_4_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "VERSE_PICKING_4_4_6TH_ROOT",
                        "5th_string": "VERSE_PICKING_4_4_5TH_ROOT",
                        "4th_string": "VERSE_PICKING_4_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "CHORUS_STRUM_4_4_6TH_ROOT",
                        "5th_string": "CHORUS_STRUM_4_4_5TH_ROOT",
                        "4th_string": "CHORUS_STRUM_4_4_4TH_ROOT",
                    ],
                ],
                "3/4": [
                    "intro": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "WALTZ_CHORUS_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_CHORUS_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_CHORUS_3_4_4TH_ROOT",
                    ],
                ],
                "6/8": [
                    "intro": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "FOLK_CHORUS_6_8_6TH_ROOT",
                        "5th_string": "FOLK_CHORUS_6_8_5TH_ROOT",
                        "4th_string": "FOLK_CHORUS_6_8_4TH_ROOT",
                    ],
                ],
            ],
            "7th": [
                "4/4": [
                    "intro": [
                        "6th_string": "INTRO_ARPEGGIO_4_4_6TH_ROOT",
                        "5th_string": "INTRO_ARPEGGIO_4_4_5TH_ROOT",
                        "4th_string": "INTRO_ARPEGGIO_4_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "VERSE_PICKING_4_4_6TH_ROOT",
                        "5th_string": "VERSE_PICKING_4_4_5TH_ROOT",
                        "4th_string": "VERSE_PICKING_4_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "CHORUS_STRUM_4_4_6TH_ROOT",
                        "5th_string": "CHORUS_STRUM_4_4_5TH_ROOT",
                        "4th_string": "CHORUS_STRUM_4_4_4TH_ROOT",
                    ],
                ],
                "3/4": [
                    "intro": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "WALTZ_CHORUS_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_CHORUS_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_CHORUS_3_4_4TH_ROOT",
                    ],
                ],
                "6/8": [
                    "intro": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "FOLK_CHORUS_6_8_6TH_ROOT",
                        "5th_string": "FOLK_CHORUS_6_8_5TH_ROOT",
                        "4th_string": "FOLK_CHORUS_6_8_4TH_ROOT",
                    ],
                ],
            ],
            "Major7": [
                "4/4": [
                    "intro": [
                        "6th_string": "INTRO_ARPEGGIO_4_4_6TH_ROOT",
                        "5th_string": "INTRO_ARPEGGIO_4_4_5TH_ROOT",
                        "4th_string": "INTRO_ARPEGGIO_4_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "VERSE_PICKING_4_4_6TH_ROOT",
                        "5th_string": "VERSE_PICKING_4_4_5TH_ROOT",
                        "4th_string": "VERSE_PICKING_4_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "CHORUS_STRUM_4_4_6TH_ROOT",
                        "5th_string": "CHORUS_STRUM_4_4_5TH_ROOT",
                        "4th_string": "CHORUS_STRUM_4_4_4TH_ROOT",
                    ],
                ],
                "3/4": [
                    "intro": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "WALTZ_CHORUS_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_CHORUS_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_CHORUS_3_4_4TH_ROOT",
                    ],
                ],
                "6/8": [
                    "intro": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "FOLK_CHORUS_6_8_6TH_ROOT",
                        "5th_string": "FOLK_CHORUS_6_8_5TH_ROOT",
                        "4th_string": "FOLK_CHORUS_6_8_4TH_ROOT",
                    ],
                ],
            ],
            "Minor7": [
                "4/4": [
                    "intro": [
                        "6th_string": "INTRO_ARPEGGIO_4_4_6TH_ROOT",
                        "5th_string": "INTRO_ARPEGGIO_4_4_5TH_ROOT",
                        "4th_string": "INTRO_ARPEGGIO_4_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "VERSE_PICKING_4_4_6TH_ROOT",
                        "5th_string": "VERSE_PICKING_4_4_5TH_ROOT",
                        "4th_string": "VERSE_PICKING_4_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "CHORUS_STRUM_4_4_6TH_ROOT",
                        "5th_string": "CHORUS_STRUM_4_4_5TH_ROOT",
                        "4th_string": "CHORUS_STRUM_4_4_4TH_ROOT",
                    ],
                ],
                "3/4": [
                    "intro": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "WALTZ_INTRO_VERSE_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_INTRO_VERSE_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_INTRO_VERSE_3_4_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "WALTZ_CHORUS_3_4_6TH_ROOT",
                        "5th_string": "WALTZ_CHORUS_3_4_5TH_ROOT",
                        "4th_string": "WALTZ_CHORUS_3_4_4TH_ROOT",
                    ],
                ],
                "6/8": [
                    "intro": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "verse": [
                        "6th_string": "FOLK_INTRO_VERSE_6_8_6TH_ROOT",
                        "5th_string": "FOLK_INTRO_VERSE_6_8_5TH_ROOT",
                        "4th_string": "FOLK_INTRO_VERSE_6_8_4TH_ROOT",
                    ],
                    "chorus": [
                        "6th_string": "FOLK_CHORUS_6_8_6TH_ROOT",
                        "5th_string": "FOLK_CHORUS_6_8_5TH_ROOT",
                        "4th_string": "FOLK_CHORUS_6_8_4TH_ROOT",
                    ],
                ],
            ],
            // Add more chord types as needed
        ]

        loadData()
    }

    private func loadData() {
        chordLibrary = DataLoader.load(filename: "chords", as: ChordLibrary.self)
        drumPatternLibrary = DataLoader.load(filename: "drums", as: DrumPatternLibrary.self)
        patternLibrary = DataLoader.load(filename: "patterns", as: PatternLibrary.self)

        if chordLibrary == nil { print("Failed to load chordLibrary") }
        if drumPatternLibrary == nil { print("Failed to load drumPatternLibrary") }
        if patternLibrary == nil { print("Failed to load patternLibrary") }
        print("Loaded patternLibrary: \(String(describing: patternLibrary))")
        if let pl = patternLibrary { print("PatternLibrary keys: \(pl.keys.sorted().joined(separator: ", "))") }
    }
}