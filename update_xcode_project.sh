#!/bin/bash

# This script updates the file paths in your .pbxproj file after refactoring.

PROJECT_FILE="ChordPlayer.xcodeproj/project.pbxproj"

# Safety check
if [ ! -f "$PROJECT_FILE" ]; then
    echo "❌ Error: project.pbxproj not found at $PROJECT_FILE"
    echo "Please run this script from the root of your project directory."
    exit 1
fi

echo "✅ Found project file. Starting update..."

# Create a backup
cp "$PROJECT_FILE" "${PROJECT_FILE}.bak"
echo "✅ Backup created at ${PROJECT_FILE}.bak"

# Use a temporary file for sed to ensure compatibility (especially for macOS)
TMP_FILE=$(mktemp)

sed -e 's|path = AddChordPlayingPatternAssociationSheet.swift;|path = Views/Sheets/AddChordPlayingPatternAssociationSheet.swift;|g' \
    -e 's|path = AddDrumPatternSheetView.swift;|path = Views/Sheets/AddDrumPatternSheetView.swift;|g' \
    -e 's|path = AddPlayingPatternSheetView.swift;|path = Views/Sheets/AddPlayingPatternSheetView.swift;|g' \
    -e 's|path = AppData.swift;|path = Managers/AppData.swift;|g' \
    -e 's|path = ChordDiagramEditor.swift;|path = Views/Editors/ChordDiagramEditor.swift;|g' \
    -e 's|path = ChordDiagramView.swift;|path = Views/Components/ChordDiagramView.swift;|g' \
    -e 's|path = ChordLibraryView.swift;|path = Views/Library/ChordLibraryView.swift;|g' \
    -e 's|path = ChordPlayer.swift;|path = Players/ChordPlayer.swift;|g' \
    -e 's|path = ChordPlayerApp.swift;|path = App/ChordPlayerApp.swift;|g' \
    -e 's|path = ContentView.swift;|path = App/ContentView.swift;|g' \
    -e 's|path = CustomChordCreatorView.swift;|path = Views/Editors/CustomChordCreatorView.swift;|g' \
    -e 's|path = CustomChordLibraryView.swift;|path = Views/Library/CustomChordLibraryView.swift;|g' \
    -e 's|path = CustomChordManager.swift;|path = Managers/CustomChordManager.swift;|g' \
    -e 's|path = CustomDrumPatternLibraryView.swift;|path = Views/Library/CustomDrumPatternLibraryView.swift;|g' \
    -e 's|path = CustomDrumPatternManager.swift;|path = Managers/CustomDrumPatternManager.swift;|g' \
    -e 's|path = CustomPlayingPatternLibraryView.swift;|path = Views/Library/CustomPlayingPatternLibraryView.swift;|g' \
    -e 's|path = CustomPlayingPatternManager.swift;|path = Managers/CustomPlayingPatternManager.swift;|g' \
    -e 's|path = DataLoader.swift;|path = Managers/DataLoader.swift;|g' \
    -e 's|path = DataModels.swift;|path = Models/DataModels.swift;|g' \
    -e 's|path = DrumPatternGridView.swift;|path = Views/Components/DrumPatternGridView.swift;|g' \
    -e 's|path = DrumPlayer.swift;|path = Players/DrumPlayer.swift;|g' \
    -e 's|path = FretboardView.swift;|path = Views/Components/FretboardView.swift;|g' \
    -e 's|path = KeyboardHandler.swift;|path = Handlers/KeyboardHandler.swift;|g' \
    -e 's|path = LyricsManagerView.swift;|path = Views/Main/LyricsManagerView.swift;|g' \
    -e 's|path = MidiManager.swift;|path = Managers/MidiManager.swift;|g' \
    -e 's|path = MusicTheory.swift;|path = Managers/MusicTheory.swift;|g' \
    -e 's|path = PlayingPatternEditorView.swift;|path = Views/Editors/PlayingPatternEditorView.swift;|g' \
    -e 's|path = PlayingPatternView.swift;|path = Views/Components/PlayingPatternView.swift;|g' \
    -e 's|path = PresetManager.swift;|path = Managers/PresetManager.swift;|g' \
    -e 's|path = PresetWorkspaceView.swift;|path = Views/Main/PresetWorkspaceView.swift;|g' \
    -e 's|path = SelectDrumPatternsSheet.swift;|path = Views/Sheets/SelectDrumPatternsSheet.swift;|g' \
    -e 's|path = Assets.xcassets;|path = Resources/Assets.xcassets;|g' \
    -e 's|path = en.lproj;|path = Resources/en.lproj;|g' \
    -e 's|path = "Preview Content";|path = "Resources/Preview Content";|g' \
    -e 's|path = "zh-Hans.lproj";|path = "Resources/zh-Hans.lproj";|g' \
    "$PROJECT_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$PROJECT_FILE"

echo "✅ Project file updated."
echo "➡️ Next steps:"
echo "1. Run this script in your terminal: ./update_xcode_project.sh"
echo "2. Open your project in Xcode. It might show files in red initially."
echo "3. In Xcode, you will now see the new folder structure. You may need to manually create groups that match the new directory structure and drag the files into them for better organization within the IDE."
echo "4. Build the project to ensure everything works."
