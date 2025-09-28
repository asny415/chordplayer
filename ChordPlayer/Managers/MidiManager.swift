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

    

    init() {
        print("[MidiManager] init started")
        setupMidi()
        // Initial scan for outputs
        scanForOutputs()
        // Restore previously selected output
        if let savedID = UserDefaults.standard.value(forKey: "selectedMidiOutputID") as? MIDIUniqueID {
            print("[MidiManager] Found saved MIDI output ID: \(savedID)")
            let endpoint = findEndpoint(by: savedID)
            print("[MidiManager] Found endpoint for saved ID: \(String(describing: endpoint))")
            selectedOutput = endpoint
            print("[MidiManager] selectedOutput is now: \(String(describing: selectedOutput))")
        } else {
            print("[MidiManager] No saved MIDI output ID found.")
        }
        print("[MidiManager] init finished")
    }

    deinit {
        // Dispose MIDI resources
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

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
            print("[MidiManager] scanForOutputs found \(outputs.count) outputs.")
            self.availableOutputs = outputs
            // If no output is selected, or the selected output is no longer available, select the first one
            if self.selectedOutput == nil || !outputs.contains(where: { $0 == self.selectedOutput }) {
                print("[MidiManager] scanForOutputs: selectedOutput is nil or not available, selecting first output.")
                self.selectedOutput = outputs.first
                print("[MidiManager] scanForOutputs: selectedOutput is now \(String(describing: self.selectedOutput))")
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

    

    func sendPitchBend(value: UInt16, channel: UInt8 = 0) {
        guard let destination = selectedOutput else { return }
        midiQueue.async { [weak self] in
            Thread.current.threadPriority = 1.0
            var packet = MIDIPacket()
            packet.timeStamp = 0 // Send immediately
            packet.length = 3
            packet.data.0 = 0xE0 | channel
            packet.data.1 = UInt8(value & 0x7F)
            packet.data.2 = UInt8((value >> 7) & 0x7F)
            var packetList = MIDIPacketList(numPackets: 1, packet: packet)
            let status = MIDISend(self?.outputPort ?? MIDIPortRef(), destination, &packetList)
            if status != noErr {
                // avoid frequent logging
            }
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
    
    static let pitchBendRange: UInt8 = 8

    func setPitchBendRange(channel: UInt8) {
        guard let destination = selectedOutput else { return }
        
        let sendControlChange = { (control: UInt8, value: UInt8) in
            self.midiQueue.async { [weak self] in
                var packet = MIDIPacket()
                packet.timeStamp = 0 // Send immediately
                packet.length = 3
                packet.data.0 = 0xB0 | channel
                packet.data.1 = control
                packet.data.2 = value
                var packetList = MIDIPacketList(numPackets: 1, packet: packet)
                MIDISend(self?.outputPort ?? MIDIPortRef(), destination, &packetList)
            }
        }

        // RPN for Pitch Bend Sensitivity
        sendControlChange(101, 0) // RPN MSB
        sendControlChange(100, 0) // RPN LSB

        // Set the range
        sendControlChange(6, MidiManager.pitchBendRange) // Data Entry MSB (semitones)
        sendControlChange(38, 0) // Data Entry LSB (cents, set to 0)

        // Nullify RPN selection
        sendControlChange(101, 127)
        sendControlChange(100, 127)
    }
}