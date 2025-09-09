import Foundation
import SwiftUI
import AppKit

/// Represents a keyboard shortcut (single key + modifiers) for chords.
struct Shortcut: Codable, Equatable, Hashable {
    var key: String // single character, stored as uppercase for consistency
    var modifiersShift: Bool
    var modifiersCommand: Bool
    var modifiersControl: Bool
    var modifiersOption: Bool

    init(key: String, modifiersShift: Bool = false, modifiersCommand: Bool = false, modifiersControl: Bool = false, modifiersOption: Bool = false) {
        self.key = key.uppercased()
        self.modifiersShift = modifiersShift
        self.modifiersCommand = modifiersCommand
        self.modifiersControl = modifiersControl
        self.modifiersOption = modifiersOption
    }
    
    var stringValue: String {
        var s = ""
        if modifiersCommand { s += "cmd+" }
        if modifiersControl { s += "ctrl+" }
        if modifiersOption { s += "opt+" }
        if modifiersShift { s += "shift+" }
        s += key.lowercased()
        return s
    }

    init?(stringValue: String) {
        let parts = stringValue.lowercased().split(separator: "+")
        guard let lastPart = parts.last else { return nil }
        self.key = String(lastPart).uppercased()
        let modifiers = Set(parts.dropLast())
        self.modifiersCommand = modifiers.contains("cmd")
        self.modifiersControl = modifiers.contains("ctrl")
        self.modifiersOption = modifiers.contains("opt")
        self.modifiersShift = modifiers.contains("shift")
    }

    var displayText: String {
        var s = ""
        if modifiersCommand { s += "⌘" }
        if modifiersControl { s += "⌃" }
        if modifiersOption { s += "⌥" }
        if modifiersShift { s += "⇧" }
        s += key.uppercased()
        return s
    }
    
    /// 检查是否与另一个快捷键冲突
    func conflictsWith(_ other: Shortcut) -> Bool {
        return key == other.key &&
               modifiersShift == other.modifiersShift &&
               modifiersCommand == other.modifiersCommand &&
               modifiersControl == other.modifiersControl &&
               modifiersOption == other.modifiersOption
    }
    
    /// 检查是否是数字键（1-9）
    func isNumericKey() -> Bool {
        return key >= "1" && key <= "9" && !modifiersCommand && !modifiersControl && !modifiersOption
    }
    
    /// 检查是否与默认和弦快捷键冲突
    

    static func from(event: NSEvent) -> Shortcut? {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        // take first character
        let first = String(chars.prefix(1)).uppercased()
        let flags = event.modifierFlags
        return Shortcut(
            key: first,
            modifiersShift: flags.contains(.shift),
            modifiersCommand: flags.contains(.command),
            modifiersControl: flags.contains(.control),
            modifiersOption: flags.contains(.option)
        )
    }
}
