import Foundation
import CoreMIDI
import Darwin
import Combine
import AudioToolbox

class MidiManager: ObservableObject {
    @Published var availableOutputs: [MIDIEndpointRef] = []
    @Published var selectedOutput: MIDIEndpointRef? {
        didSet {
            // Persist selected output ID
            if let selectedOutput = selectedOutput {
                var uniqueID: Int32 = 0
                let status = MIDIObjectGetIntegerProperty(selectedOutput, kMIDIPropertyUniqueID, &uniqueID)
                if status == noErr {
                    UserDefaults.standard.set(uniqueID, forKey: "selectedMidiOutputID")
                } else {
                    print("Error getting MIDI unique ID for persistence: \(status)")
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedMidiOutputID")
            }
        }
    }

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    // Serial high-priority queue for MIDI sends
    private let midiQueue = DispatchQueue(label: "com.guitastudio.midi", qos: .userInteractive)
    // Pending scheduled events that have not yet been handed to CoreMIDI
    private struct PendingEvent {
        let id: UUID
        let note: UInt8
        let velocity: UInt8
        let channel: UInt8
        let isNoteOn: Bool
        let scheduledUptimeMs: Double
    }
    // map id -> PendingEvent (accessed only on midiQueue)
    private var pendingEvents: [UUID: PendingEvent] = [:]
    // lead time (ms) to hand events off to CoreMIDI - send when event within this window
    private let leadMs: Double = 25.0
    private var schedulerTimer: DispatchSourceTimer?

    init() {
        setupMidi()
        // Initial scan for outputs
        scanForOutputs()
        // Restore previously selected output
        if let savedID = UserDefaults.standard.value(forKey: "selectedMidiOutputID") as? MIDIUniqueID {
            selectedOutput = findEndpoint(by: savedID)
        }
        // start scheduler timer on midiQueue
        startScheduler()
    }

    deinit {
        stopScheduler()
        // Dispose MIDI resources
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

    private func startScheduler() {
        schedulerTimer = DispatchSource.makeTimerSource(queue: midiQueue)
        schedulerTimer?.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        schedulerTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.flushDueEvents()
        }
        schedulerTimer?.resume()
    }

    private func stopScheduler() {
        schedulerTimer?.cancel()
        schedulerTimer = nil
    }

    private func flushDueEvents() {
        // called on midiQueue
        guard !pendingEvents.isEmpty else { return }
        let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        var toSend: [PendingEvent] = []
        for (_, ev) in pendingEvents {
            if ev.scheduledUptimeMs - nowUptimeMs <= leadMs {
                toSend.append(ev)
            }
        }
        // sort by scheduled time
        toSend.sort { $0.scheduledUptimeMs < $1.scheduledUptimeMs }
        for ev in toSend {
            // remove from pending map
            pendingEvents.removeValue(forKey: ev.id)
            // compute mach timestamp
            let machTime = self.machTimeForScheduledUptimeMs(ev.scheduledUptimeMs)
            var packet = MIDIPacket()
            packet.timeStamp = machTime
            packet.length = 3
            packet.data.0 = (ev.isNoteOn ? 0x90 : 0x80) | ev.channel
            packet.data.1 = ev.note
            packet.data.2 = ev.velocity
            var packetList = MIDIPacketList(numPackets: 1, packet: packet)
            if let destination = self.selectedOutput {
                MIDISend(self.outputPort, destination, &packetList)
            }
        }
    }

    // removed duplicate deinit - cleanup done in single deinit above

    private func setupMidi() {
        var status = MIDIClientCreateWithBlock("ChordPlayer MIDI Client" as CFString, &client) { notification in
            // Handle MIDI notifications (e.g., device added/removed)
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
                self.scanForOutputs()
            default:
                break
            }
        }
        if status != noErr {
            print("Error creating MIDI client: \(status)")
            return
        }

        status = MIDIOutputPortCreate(client, "ChordPlayer Output Port" as CFString, &outputPort)
        if status != noErr {
            print("Error creating MIDI output port: \(status)")
            return
        }
    }

    func scanForOutputs() {
        var outputs: [MIDIEndpointRef] = []
        let sourceCount = MIDIGetNumberOfDestinations()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetDestination(i)
            outputs.append(endpoint)
        }
        DispatchQueue.main.async {
            self.availableOutputs = outputs
            // If no output is selected, or the selected output is no longer available, select the first one
            if self.selectedOutput == nil || !outputs.contains(where: { $0 == self.selectedOutput }) {
                self.selectedOutput = outputs.first
            }
        }
    }

    func displayName(for endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        return name?.takeRetainedValue() as String? ?? "Unknown MIDI Device"
    }

    private func findEndpoint(by uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        let sourceCount = MIDIGetNumberOfDestinations()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetDestination(i)
            var currentID: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &currentID)
            if status == noErr && currentID == uniqueID {
                return endpoint
            }
        }
        return nil
    }

    func sendNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard let destination = selectedOutput else {
            // No output - nothing to do
            return
        }

        // Enqueue MIDI send on a dedicated high-priority serial queue to
        // minimize scheduling jitter and contention.
        midiQueue.async { [weak self] in
            // slight increase of thread priority within allowed range
            Thread.current.threadPriority = 1.0
            var packet = MIDIPacket()
            packet.timeStamp = 0 // Send immediately
            packet.length = 3
            packet.data.0 = 0x90 | channel // Note On message (0x90) + channel
            packet.data.1 = note          // MIDI Note Number
            packet.data.2 = velocity      // Velocity

            var packetList = MIDIPacketList(numPackets: 1, packet: packet)
            let status = MIDISend(self?.outputPort ?? MIDIPortRef(), destination, &packetList)
            if status != noErr {
                // avoid frequent logging in hot path
            }
        }
    }

    // Convert scheduled uptime (ms, based on ProcessInfo.processInfo.systemUptime*1000)
    // into a MIDITimeStamp (mach absolute time units) for time-stamped MIDI sends.
    private func machTimeForScheduledUptimeMs(_ scheduledUptimeMs: Double) -> UInt64 {
        // compute delta from now (uptime)
        let nowUptimeMs = ProcessInfo.processInfo.systemUptime * 1000.0
        let deltaMs = scheduledUptimeMs - nowUptimeMs
        if deltaMs <= 0 {
            return 0 // indicate immediate
        }

        // convert delta milliseconds to nanoseconds
        let deltaNs = UInt64(deltaMs * 1_000_000.0)

        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        // mach units -> ns : ns = mach * numer / denom
        // so mach = ns * denom / numer
        let deltaMach = UInt64(Double(deltaNs) * Double(info.denom) / Double(info.numer))
        let nowMach = mach_absolute_time()
        return nowMach + deltaMach
    }

    // Schedule a Note On at a specific uptime (ms). If scheduledUptimeMs is nil
    // or in the past, the note is sent immediately.
    // Schedule a Note On to be sent at scheduledUptimeMs (ms, uptime basis).
    // Returns a UUID token which can be used to cancel before the scheduler hands it to CoreMIDI.
    @discardableResult
    func scheduleNoteOn(note: UInt8, velocity: UInt8, channel: UInt8 = 0, scheduledUptimeMs: Double) -> UUID {
        let id = UUID()
        let ev = PendingEvent(id: id, note: note, velocity: velocity, channel: channel, isNoteOn: true, scheduledUptimeMs: scheduledUptimeMs)
        midiQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingEvents[id] = ev
        }
        return id
    }

    @discardableResult
    func scheduleNoteOff(note: UInt8, velocity: UInt8, channel: UInt8 = 0, scheduledUptimeMs: Double) -> UUID {
        let id = UUID()
        let ev = PendingEvent(id: id, note: note, velocity: velocity, channel: channel, isNoteOn: false, scheduledUptimeMs: scheduledUptimeMs)
        midiQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingEvents[id] = ev
        }
        return id
    }

    func cancelScheduledEvent(id: UUID) {
        midiQueue.async { [weak self] in
            self?.pendingEvents.removeValue(forKey: id)
        }
    }

    func cancelAllPendingScheduledEvents() {
        midiQueue.async { [weak self] in
            self?.pendingEvents.removeAll()
        }
    }

    

    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard let destination = selectedOutput else { return }
        midiQueue.async { [weak self] in
            Thread.current.threadPriority = 1.0
            var packet = MIDIPacket()
            packet.timeStamp = 0
            packet.length = 3
            packet.data.0 = 0x80 | channel
            packet.data.1 = note
            packet.data.2 = velocity
            var packetList = MIDIPacketList(numPackets: 1, packet: packet)
            let status = MIDISend(self?.outputPort ?? MIDIPortRef(), destination, &packetList)
            if status != noErr {
                // avoid frequent logging
            }
        }
    }

    func sendPanic() {
        guard let destination = selectedOutput else { return }
        midiQueue.async { [weak self] in
            Thread.current.threadPriority = 1.0
            for channel: UInt8 in 0..<16 {
                var packet = MIDIPacket()
                packet.timeStamp = 0
                packet.length = 3
                packet.data.0 = 0xB0 | channel
                packet.data.1 = 123
                packet.data.2 = 0
                var packetList = MIDIPacketList(numPackets: 1, packet: packet)
                let status = MIDISend(self?.outputPort ?? MIDIPortRef(), destination, &packetList)
                if status != noErr {
                    // ignore logging in the hot path
                }
            }
        }
    }
}
