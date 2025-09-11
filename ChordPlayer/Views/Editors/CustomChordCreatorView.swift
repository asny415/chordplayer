import SwiftUI

struct CustomChordCreatorView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var chordPlayer: ChordPlayer
    @EnvironmentObject var midiManager: MidiManager
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var customChordManager = CustomChordManager.shared
    
    // --- State ---
    @State private var chordName: String = ""
    // New state for the interactive fretboard, using simple integers.
    // -1 = muted, 0 = open, >0 = fret number.
    @State private var frets: [Int] = Array(repeating: -1, count: 6)
    // New state to control the position/offset of the fretboard view.
    @State private var fretPosition: Int = 1
    
    // This remains for saving/compatibility with the existing system.
    // It's updated automatically when `frets` changes.
    @State private var fingering: [StringOrInt] = []

    @State private var showingNameConflictAlert = false
    @State private var showingSaveSuccessAlert = false
    @State private var isPlaying = false
    
    private let maxNameLength = 50
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    nameInputSection
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    // --- New Fretboard Implementation ---
                    FretboardView(frets: $frets, fretPosition: $fretPosition)
                    
                    Stepper("把位 (Fret Position): \(fretPosition)", value: $fretPosition, in: 1...15)
                        .padding(.horizontal, 24)

                    if !hasValidFingering() {
                        Text("和弦指法至少需要1个有效音（按品或空弦）。")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }
                    
                    previewSection
                        .padding(.horizontal, 24)
                    
                    actionButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 650, idealHeight: 700) // Increased height for new layout
        .background(Color(NSColor.windowBackgroundColor))
        .alert("和弦名称冲突", isPresented: $showingNameConflictAlert) {
            Button("取消", role: .cancel) { }
            Button("覆盖") { saveChord(overwrite: true) }
        } message: {
            Text("和弦名称 \"\(chordName)\" 已存在。是否要覆盖现有的和弦？")
        }
        .alert("保存成功", isPresented: $showingSaveSuccessAlert) {
            Button("确定") { dismiss() }
        } message: {
            Text("自定义和弦 \"\(chordName)\" 已成功保存！")
        }
        .onChange(of: frets) { newFrets in
            // Synchronize the new `frets` array with the old `fingering` array
            // to maintain compatibility with the saving mechanism.
            self.fingering = newFrets.map { fret in
                if fret < 0 {
                    return .string("x")
                } else {
                    return .int(fret)
                }
            }
        }
        .onAppear(perform: clearAll) // Start with a clean slate
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("创建自定义和弦")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("使用可视化指板编辑器创建您的专属和弦")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("取消", role: .cancel) { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(20)
    }
    
    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("和弦名称")
                    .font(.headline)
                Spacer()
                Text("\(chordName.count)/\(maxNameLength)")
                    .font(.caption)
                    .foregroundColor(chordName.count > maxNameLength ? .red : .secondary)
            }
            TextField("例如: C_Custom, Am7_Custom", text: $chordName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: chordName) { newValue in
                    if newValue.count > maxNameLength {
                        chordName = String(newValue.prefix(maxNameLength))
                    }
                }
            if chordName.isEmpty {
                Text("请输入和弦名称").font(.caption).foregroundColor(.red)
            }
        }
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预览和试听").font(.headline)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("指法:").font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { stringIndex in
                            Text(fingeringDisplayText(from: frets[stringIndex]))
                                .font(.caption).fontWeight(.medium).foregroundColor(.primary)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.controlBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 1))
                        }
                    }
                }
                Spacer()
                Button(action: playChord) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        Text(isPlaying ? "停止" : "试听")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave())
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("清空") { clearAll() }.buttonStyle(.bordered)
            Spacer()
            Button("保存") { saveChord(overwrite: false) }.buttonStyle(.borderedProminent).disabled(!canSave())
        }
    }
    
    // --- Updated Logic ---
    
    private func hasValidFingering() -> Bool {
        // A valid chord must have at least one sounding note (not muted).
        return frets.contains { $0 >= 0 }
    }
    
    private func canSave() -> Bool {
        return !chordName.trimmingCharacters(in: .whitespaces).isEmpty && chordName.count <= maxNameLength && hasValidFingering()
    }
    
    private func clearAll() {
        chordName = ""
        frets = [0, 0, 0, 0, 0, 0] // Default to all open strings
        fretPosition = 1
    }
    
    private func playChord() {
        if isPlaying {
            midiManager.sendPanic()
            isPlaying = false
        } else {
            let notesToPlay = MusicTheory.chordToMidiNotes(chordDefinition: fingering, tuning: MusicTheory.standardGuitarTuning)
                .filter { $0 >= 0 } // Filter out muted strings

            guard !notesToPlay.isEmpty else { return }

            isPlaying = true
            
            for note in notesToPlay {
                midiManager.sendNoteOn(note: UInt8(note), velocity: 100)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if isPlaying { // Only stop if it's still in the playing state
                    for note in notesToPlay {
                        midiManager.sendNoteOff(note: UInt8(note), velocity: 100)
                    }
                    isPlaying = false
                }
            }
        }
    }
    
    private func saveChord(overwrite: Bool) {
        let trimmedName = chordName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        if customChordManager.chordExists(name: trimmedName) && !overwrite {
            showingNameConflictAlert = true
            return
        }
        customChordManager.addChord(name: trimmedName, fingering: self.fingering)
        showingSaveSuccessAlert = true
    }
    
    private func fingeringDisplayText(from fret: Int) -> String {
        if fret < 0 {
            return "×"
        } else {
            return "\(fret)"
        }
    }
}