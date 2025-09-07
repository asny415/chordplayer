import Foundation

// Tiny test harness to exercise PresetManager initialization in a script.
// Note: This file lives outside the app target; it loads Preset files directly.

let fm = FileManager.default
let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
let base = docs.appendingPathComponent("ChordPlayer")
let presetsDir = base.appendingPathComponent("Presets")

print("Document base: \(base.path)")
print("Presets dir: \(presetsDir.path)")

if fm.fileExists(atPath: presetsDir.path) {
    do {
        let files = try fm.contentsOfDirectory(at: presetsDir, includingPropertiesForKeys: nil)
        print("Found \(files.count) files in presets dir:")
        for f in files { print(" - \(f.lastPathComponent)") }
    } catch {
        print("Failed to list presets dir: \(error)")
    }
} else {
    print("Presets directory does not exist yet.")
}

// We can't easily instantiate the app's PresetManager singleton from this script
// because it's part of the app module. This script only verifies file-level effects.
print("Script done.")
