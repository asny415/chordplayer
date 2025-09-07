
import SwiftUI

struct PlayingPatternEditorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var customPlayingPatternManager: CustomPlayingPatternManager

    // Form state
    @State private var id: String = ""
    @State private var name: String = ""
    @State private var timeSignature: String = "4/4"
    @State private var subdivision: Int = 8 // 8th notes

    // Simplified representation of the timeline actions
    @State private var actions: [EditorAction?] = Array(repeating: nil, count: 8)

    let editingPatternData: PlayingPatternEditorData?
    private var isEditing: Bool { editingPatternData != nil }

    // Represents an action in the editor timeline
    enum EditorAction: Hashable {
        case strumDown
        case strumUp
        case pluck(notes: [NoteValue])
        case mute
    }

    init(editingPatternData: PlayingPatternEditorData? = nil) {
        self.editingPatternData = editingPatternData
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "编辑演奏模式" : "创建新演奏模式")
                .font(.largeTitle).fontWeight(.bold).padding()

            ScrollView {
                VStack(spacing: 20) {
                    Form {
                        TextField("唯一ID (e.g., my_awesome_pattern)", text: $id)
                            .disabled(isEditing)
                        TextField("显示名称 (e.g., 我的分解节奏)", text: $name)
                        
                        Picker("拍子", selection: $timeSignature) {
                            Text("4/4").tag("4/4")
                            Text("3/4").tag("3/4")
                            Text("6/8").tag("6/8")
                        }
                        
                        Picker("精度", selection: $subdivision) {
                            Text("8分音符").tag(8)
                            Text("16分音符").tag(16)
                        }
                    }.padding(.bottom)

                    Divider()
                    
                    // Placeholder for the timeline editor
                    Text("时序编辑器 (待实现)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(height: 200)

                }.padding()
            }

            Divider()
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
            }.padding()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 550)
        .onAppear(perform: setupInitialState)
        .onChange(of: timeSignature) { _ in updateTimelineSize() }
        .onChange(of: subdivision) { _ in updateTimelineSize() }
    }

    private func setupInitialState() {
        if let data = editingPatternData {
            self.id = data.id
            self.name = data.pattern.name
            self.timeSignature = data.timeSignature
            // Simplified logic
            if let firstEvent = data.pattern.pattern.first, firstEvent.delay.contains("16") {
                self.subdivision = 16
            } else {
                self.subdivision = 8
            }
            // TODO: Convert pattern events to editor actions
            updateTimelineSize()
        }
    }

    private func updateTimelineSize() {
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let columns = beats * (subdivision == 8 ? 2 : 4)
        actions = Array(repeating: nil, count: columns)
    }

    private func save() {
        // TODO: Implement the conversion from `actions` to `[PatternEvent]`
        // This is a complex task and will be a placeholder for now.
        let patternEvents: [PatternEvent] = [] 

        let newPattern = GuitarPattern(id: id, name: name, pattern: patternEvents)
        customPlayingPatternManager.addOrUpdatePattern(pattern: newPattern, timeSignature: timeSignature)
        dismiss()
    }
}
