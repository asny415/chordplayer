import SwiftUI

/// 吉他指板编辑器
struct FretboardEditor: View {
    @Binding var fingering: [StringOrInt]
    @State private var selectedString: Int? = nil
    @State private var hoveredFret: (string: Int, fret: Int)? = nil
    
    private let stringNames = ["E", "B", "G", "D", "A", "E"]
    private let fretCount = 10
    private let fretWidth: CGFloat = 24
    private let stringHeight: CGFloat = 4
    private let stringSpacing: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 8) {
            // 指板标题
            HStack {
                Text("指板编辑器")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button("清空") {
                    clearFingering()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            
            // 指板主体
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                
                VStack(spacing: 0) {
                    // 弦名标签
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { stringIndex in
                            Text(stringNames[stringIndex])
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // 指板网格
                    HStack(spacing: 0) {
                        // 弦名列
                        VStack(spacing: stringSpacing) {
                            ForEach(0..<6, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: 20, height: stringHeight)
                            }
                        }
                        
                        // 指板内容
                        VStack(spacing: stringSpacing) {
                            ForEach(0..<6, id: \.self) { stringIndex in
                                HStack(spacing: 0) {
                                    ForEach(0..<fretCount, id: \.self) { fretIndex in
                                        fretButton(stringIndex: stringIndex, fretIndex: fretIndex)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .frame(height: 140)
            .padding(.horizontal)
            
            // 指法显示
            fingeringDisplay
        }
    }
    
    // MARK: - 子视图
    
    private func fretButton(stringIndex: Int, fretIndex: Int) -> some View {
        let isSelected = isFretSelected(stringIndex: stringIndex, fretIndex: fretIndex)
        let isHovered = hoveredFret?.string == stringIndex && hoveredFret?.fret == fretIndex
        
        return Button(action: {
            toggleFret(stringIndex: stringIndex, fretIndex: fretIndex)
        }) {
            ZStack {
                // 背景
                RoundedRectangle(cornerRadius: 4)
                    .fill(buttonBackgroundColor(isSelected: isSelected, isHovered: isHovered))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(buttonBorderColor(isSelected: isSelected), lineWidth: 1)
                    )
                
                // 内容
                if isSelected {
                    if case .string(let s) = fingering[stringIndex], s == "x" {
                        Text("×")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    } else if case .int(let fret) = fingering[stringIndex] {
                        Text("\(fret)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                } else {
                    Text("\(fretIndex)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: fretWidth, height: stringHeight)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredFret = (stringIndex, fretIndex)
            } else if hoveredFret?.string == stringIndex && hoveredFret?.fret == fretIndex {
                hoveredFret = nil
            }
        }
    }
    
    private var fingeringDisplay: some View {
        HStack(spacing: 12) {
            Text("指法:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { stringIndex in
                    let value = fingering[stringIndex]
                    Text(fingeringDisplayText(value))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - 辅助方法
    
    private func isFretSelected(stringIndex: Int, fretIndex: Int) -> Bool {
        let currentValue = fingering[stringIndex]
        switch currentValue {
        case .string("x"):
            return fretIndex == 0 // "x" 表示不弹奏，显示在第0品
        case .string(_):
            return false // 其他字符串值不选中任何品位
        case .int(let fret):
            return fret == fretIndex
        }
    }
    
    private func toggleFret(stringIndex: Int, fretIndex: Int) {
        let currentValue = fingering[stringIndex]
        
        switch currentValue {
        case .string("x"):
            // 从不弹奏切换到弹奏
            fingering[stringIndex] = .int(fretIndex)
        case .string(_):
            // 其他字符串值，设为不弹奏
            fingering[stringIndex] = .string("x")
        case .int(let currentFret):
            if currentFret == fretIndex {
                // 取消选择，设为不弹奏
                fingering[stringIndex] = .string("x")
            } else {
                // 选择新的品位
                fingering[stringIndex] = .int(fretIndex)
            }
        }
    }
    
    private func clearFingering() {
        fingering = Array(repeating: .string("x"), count: 6)
    }
    
    private func buttonBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    private func buttonBorderColor(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        } else {
            return Color(NSColor.separatorColor)
        }
    }
    
    private func fingeringDisplayText(_ value: StringOrInt) -> String {
        switch value {
        case .string("x"):
            return "×"
        case .int(let fret):
            return "\(fret)"
        case .string(let s):
            return s
        }
    }
}

// MARK: - 预览
struct FretboardEditor_Previews: PreviewProvider {
    @State static var sampleFingering: [StringOrInt] = [
        .string("x"), .int(3), .int(2), .int(0), .int(1), .int(0)
    ]
    
    static var previews: some View {
        FretboardEditor(fingering: $sampleFingering)
            .frame(width: 400, height: 300)
            .padding()
    }
}
