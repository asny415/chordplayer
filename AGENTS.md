# Repository Guidelines

## Project Structure & Module Organization
The macOS SwiftUI app lives in `ChordPlayer/`, with entry points in `App/` and reusable UI under `Views/` (notably `Views/Components` for atoms and `Views/Main` for the workspace shell). Shared business logic sits in `Managers/` and `Handlers/`, while audio scheduling engines reside in `Players/`. Data models are centralized in `Models/`, app assets under `Resources/`, and bundled JSON presets in `Data/`. Unit and UI targets stay in `ChordPlayerTests/` and `ChordPlayerUITests/`, and additional architecture notes are tracked in `docs/`.

## Build, Test, and Development Commands
Open the workspace in Xcode with `open ChordPlayer.xcodeproj` for GUI workflows. Use `xcodebuild -scheme ChordPlayer -configuration Debug build -destination 'platform=macOS'` to ensure the macOS target compiles headlessly. Run unit coverage via `xcodebuild test -scheme ChordPlayer -destination 'platform=macOS'`. When validating preset IO from the command line, `swift scripts/preset_manager_test.swift` prints the detected Documents/ChordPlayer presets and highlights missing directories.

## Coding Style & Naming Conventions
Follow Swift 5 defaults with four-space indentation and trailing commas for multiline literals. Keep types in UpperCamelCase, instances and functions in lowerCamelCase, and prefer value types (`struct`, `enum`) for models defined in `Models/`. Group related extensions with `// MARK:` anchors and co-locate mocks beside the tests that need them. When touching JSON assets, maintain the existing snake_case keys and alphabetical ordering.

## Testing Guidelines
XCTest is the standard; mirror the existing `test01_` numbering in `ChordPlayerTests/guitarPlayerTests.swift` to express execution order. Create explicit `XCTestExpectation` objects for async Combine or MIDI timing assertions and clean up cancellables in `tearDown()`. Aim to extend coverage whenever touching `Managers/` or `Players/`, especially around scheduling and state resets. Execute focused suites with `xcodebuild test -scheme ChordPlayer -only-testing:ChordPlayerTests/DrumPlayerTests` before pushing.

## Commit & Pull Request Guidelines
Match the repository's concise, action-first commit titles (often in Chinese, e.g., `正确画网格`). Keep summaries under 40 characters, omit trailing punctuation, and group related edits into single commits. Pull requests should describe behavior changes, list touched modules, link issues if available, and attach before/after screenshots or MIDI captures when UI or timing change. Confirm the Debug build and targeted tests pass locally and note any follow-up work explicitly.

## Security & Configuration Tips
Guard API keys or sample content—none should land in `Resources/`. Treat user preset folders as optional; the app generates defaults on first launch. Regenerate icons with `python3 generate_icons.py` only after updating `icon_design.svg`, and re-run `update_xcode_project.sh` whenever new localized resources are added to keep the project file synchronized.
