import Foundation
import SwiftUI
import AppKit

/// Represents a keyboard shortcut (single key + modifiers) for chords.
struct Shortcut: Codable, Equatable {
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
    func conflictsWithDefaultChordShortcut(for chordName: String) -> Bool {
        // 检查Major和弦：小写字母
        if chordName.hasSuffix("_Major") {
            let letter = String(chordName.prefix(1))
            return key == letter.uppercased() && !modifiersShift && !modifiersCommand && !modifiersControl && !modifiersOption
        }
        
        // 检查Minor和弦：Shift+大写字母
        if chordName.hasSuffix("_Minor") {
            let letter = String(chordName.prefix(1))
            return key == letter.uppercased() && modifiersShift && !modifiersCommand && !modifiersControl && !modifiersOption
        }
        
        // 检查其他和弦类型的默认快捷键
        if chordName.hasSuffix("7") {
            let letter = String(chordName.prefix(1))
            return key == letter.uppercased() && modifiersControl && !modifiersShift && !modifiersCommand && !modifiersOption
        }
        
        if chordName.hasSuffix("_Major7") {
            let letter = String(chordName.prefix(1))
            return key == letter.uppercased() && modifiersCommand && !modifiersShift && !modifiersControl && !modifiersOption
        }
        
        if chordName.hasSuffix("_Minor7") {
            let letter = String(chordName.prefix(1))
            return key == letter.uppercased() && modifiersOption && !modifiersShift && !modifiersCommand && !modifiersControl
        }
        
        return false
    }

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
