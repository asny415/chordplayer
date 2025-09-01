import Foundation
import CoreMIDI
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

    init() {
        setupMidi()
        // Initial scan for outputs
        scanForOutputs()
        // Restore previously selected output
        if let savedID = UserDefaults.standard.value(forKey: "selectedMidiOutputID") as? MIDIUniqueID {
            selectedOutput = findEndpoint(by: savedID)
        }
    }

    deinit {
        MIDIClientDispose(client)
    }

    private func setupMidi() {
        var status = MIDIClientCreateWithBlock("GuitarPlayer MIDI Client" as CFString, &client) { notification in
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

        status = MIDIOutputPortCreate(client, "GuitarPlayer Output Port" as CFString, &outputPort)
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
            print("No MIDI output selected.")
            return
        }

        var packet = MIDIPacket()
        packet.timeStamp = 0 // Send immediately
        packet.length = 3
        packet.data.0 = 0x90 | channel // Note On message (0x90) + channel
        packet.data.1 = note          // MIDI Note Number
        packet.data.2 = velocity      // Velocity

        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        let status = MIDISend(outputPort, destination, &packetList)
        if status != noErr {
            print("Error sending MIDI note on: \(status)")
        }
    }

    func sendNoteOff(note: UInt8, velocity: UInt8, channel: UInt8 = 0) {
        guard let destination = selectedOutput else {
            print("No MIDI output selected.")
            return
        }

        var packet = MIDIPacket()
        packet.timeStamp = 0 // Send immediately
        packet.length = 3
        packet.data.0 = 0x80 | channel // Note Off message (0x80) + channel
        packet.data.1 = note          // MIDI Note Number
        packet.data.2 = velocity      // Velocity

        var packetList = MIDIPacketList(numPackets: 1, packet: packet)
        let status = MIDISend(outputPort, destination, &packetList)
        if status != noErr {
            print("Error sending MIDI note off: \(status)")
        }
    }

    func sendPanic() {
        guard let destination = selectedOutput else {
            print("No MIDI output selected for panic.")
            return
        }

        // Send All Notes Off (Controller 123) for all channels
        for channel: UInt8 in 0..<16 {
            var packet = MIDIPacket()
            packet.timeStamp = 0
            packet.length = 3
            packet.data.0 = 0xB0 | channel // Control Change message (0xB0) + channel
            packet.data.1 = 123           // All Notes Off controller
            packet.data.2 = 0             // Value (ignored for All Notes Off)

            var packetList = MIDIPacketList(numPackets: 1, packet: packet)
            let status = MIDISend(outputPort, destination, &packetList)
            if status != noErr {
                print("Error sending MIDI panic: \(status)")
            }
        }
    }
}
