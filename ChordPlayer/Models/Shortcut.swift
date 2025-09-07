import Foundation
import SwiftUI
import AppKit

/// Represents a keyboard shortcut (single key + modifiers) for chords.
struct Shortcut: Codable, Equatable {
    var key: String // single character, stored as uppercase for consistency
    var modifiersShift: Bool

    init(key: String, modifiersShift: Bool = false) {
        self.key = key.uppercased()
        self.modifiersShift = modifiersShift
    }

    var displayText: String {
        var s = ""
        if modifiersShift { s += "⇧" }
        s += key.uppercased()
        return s
    }

    static func from(event: NSEvent) -> Shortcut? {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        // take first character
        let first = String(chars.prefix(1)).uppercased()
        let shift = event.modifierFlags.contains(.shift)
        return Shortcut(key: first, modifiersShift: shift)
    }
}
