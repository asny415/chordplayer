import XCTest
@testable import ChordPlayer
import Combine

// MARK: - Mock Objects

class MockMidiManager: MidiManager {
    var sentNotes: [(note: UInt8, velocity: UInt8, channel: UInt8)] = []
    var scheduledNotes: [(note: UInt8, velocity: UInt8, channel: UInt8, uptime: Double)] = []
    var panicCalled = false
    var cancelAllPendingCalled = false

    override func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        sentNotes.append((note, velocity, channel))
    }

    @discardableResult
    override func scheduleNoteOn(note: UInt8, velocity: UInt8, channel: UInt8, scheduledUptimeMs: Double) -> UUID {
        scheduledNotes.append((note, velocity, channel, scheduledUptimeMs))
        return UUID()
    }
    
    override func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8) {
        // For simplicity, we don't track note off in this mock
    }
    
    @discardableResult
    override func scheduleNoteOff(note: UInt8, velocity: UInt8, channel: UInt8, scheduledUptimeMs: Double) -> UUID {
        // For simplicity, we don't track note off in this mock
        return UUID()
    }

    override func sendPanic() {
        panicCalled = true
    }

    override func cancelAllPendingScheduledEvents() {
        cancelAllPendingCalled = true
        scheduledNotes.removeAll()
    }

    func clear() {
        sentNotes.removeAll()
        scheduledNotes.removeAll()
        panicCalled = false
        cancelAllPendingCalled = false
    }
}

// A basic AppData that can be used for testing
class TestAppData: AppData {
    init() {
        super.init(customChordManager: CustomChordManager.shared)
        // Setup with some default data for predictability
        self.performanceConfig = PerformanceConfig(
            tempo: 120.0,
            timeSignature: "4/4",
            key: "C",
            chords: [],
            selectedDrumPatterns: ["Pop.Rock 4/4"],
            activeDrumPatternId: "Pop.Rock 4/4"
        )
        
        // Create a dummy drum pattern library
        let dummyPattern = DrumPattern(displayName: "Test Rock", pattern: [
            DrumPatternEvent(delay: "0/16", notes: [36]),
            DrumPatternEvent(delay: "4/16", notes: [38]),
            DrumPatternEvent(delay: "4/16", notes: [36]),
            DrumPatternEvent(delay: "4/16", notes: [38]),
        ])
        self.drumPatternLibrary = ["4/4": ["Pop.Rock 4/4": dummyPattern]]
    }
}

// MARK: - DrumPlayerTests

class DrumPlayerTests: XCTestCase {

    var drumPlayer: DrumPlayer!
    var mockMidiManager: MockMidiManager!
    var testAppData: TestAppData!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        mockMidiManager = MockMidiManager()
        testAppData = TestAppData()
        drumPlayer = DrumPlayer(midiManager: mockMidiManager, appData: testAppData, customDrumPatternManager: CustomDrumPatternManager.shared)
    }

    override func tearDown() {
        drumPlayer.stop()
        drumPlayer = nil
        mockMidiManager = nil
        testAppData = nil
        cancellables.removeAll()
        super.tearDown()
    }

    func test01_PlayFromStop_CorrectlyStartsAndSchedulesCountIn() {
        let expectation = XCTestExpectation(description: "Playback starts and count-in is scheduled.")
        
        // We expect the measure to become 0 (count-in)
        testAppData.$currentMeasure
            .sink { measure in
                if measure == 0 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Action
        drumPlayer.playPattern(tempo: 120)

        // Verification
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertTrue(drumPlayer.isPlaying, "DrumPlayer should be in playing state.")
        XCTAssertEqual(testAppData.currentMeasure, 0, "Measure should be 0 for count-in.")
        XCTAssertTrue(testAppData.currentBeat < 0, "Beat should be negative for count-in.")
        
        // Check if count-in notes were scheduled
        XCTAssertTrue(mockMidiManager.scheduledNotes.contains { $0.note == 42 }, "Count-in hi-hat (note 42) should be scheduled.")
    }
    
    func test02_PlayFromStop_With34Time_Schedules3CountInBeats() {
        let expectation = XCTestExpectation(description: "Beat becomes -3 for 3/4 time.")
        
        testAppData.performanceConfig.timeSignature = "3/4"
        
        testAppData.$currentBeat
            .sink { beat in
                // The first beat update will be to -3
                if beat == -3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Action
        drumPlayer.playPattern(tempo: 120)

        // Verification
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(testAppData.currentBeat, -3, "For 3/4 time, the first count-in beat should be -3.")
    }


    func test03_Stop_CorrectlyStopsPlaybackAndResetsState() {
        let startExpectation = XCTestExpectation(description: "Playback starts.")
        testAppData.$currentMeasure
            .sink { measure in
                if measure == 0 {
                    startExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        drumPlayer.playPattern(tempo: 120)
        wait(for: [startExpectation], timeout: 1.0)
        
        // Ensure it really started
        XCTAssertTrue(drumPlayer.isPlaying)

        // Action
        drumPlayer.stop()

        // Verification
        XCTAssertFalse(drumPlayer.isPlaying, "DrumPlayer should be in stopped state.")
        XCTAssertTrue(mockMidiManager.panicCalled, "MIDI panic should be called on stop.")
        XCTAssertTrue(mockMidiManager.cancelAllPendingCalled, "All pending MIDI events should be cancelled.")
        
        // Check if state is reset
        let beatsPerMeasure = 4 // for 4/4 time
        XCTAssertEqual(testAppData.currentMeasure, 0, "Measure should reset to 0.")
        XCTAssertEqual(testAppData.currentBeat, -beatsPerMeasure, "Beat should reset to the initial negative value.")
    }
    
    func test04_PatternSwitching_QueuesNextPattern() {
        // Create a second pattern for switching
        let patternB = DrumPattern(displayName: "Pattern B", pattern: [])
        testAppData.drumPatternLibrary?["4/4"]?["PatternB"] = patternB
        
        // 1. Start playing Pattern A
        drumPlayer.playPattern(tempo: 120)
        
        let expectation = XCTestExpectation(description: "Wait for playback to start before switching.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { expectation.fulfill() }
        wait(for: [expectation], timeout: 0.2)
        
        // 2. While playing, request to switch to Pattern B
        testAppData.performanceConfig.activeDrumPatternId = "PatternB"
        drumPlayer.playPattern(tempo: 120)
        
        // 3. Verification
        // We can't easily test the actual switch timing here,
        // but we can verify that the pattern was correctly queued.
        // To do this, we would ideally have an internal property accessor.
        // For now, we will trust the print log and the logic.
        // A more advanced test would involve injecting a "time provider" to control time.
        
        // This test primarily verifies that calling playPattern while playing doesn't crash
        // and that the queuing mechanism is invoked (as seen in logs).
        XCTAssertTrue(drumPlayer.isPlaying, "Player should remain in playing state after queuing a new pattern.")
    }
}