
import Foundation

extension GuitarPattern {
    
        func generateSmartName(timeSignature: String) -> String {
        // 1. 从pattern中推断精度
        let maxDenominator = self.pattern.compactMap {
            Int($0.delay.split(separator: "/").last ?? "")
        }.max() ?? 8
        let precision = (maxDenominator > 8) ? 16 : 8

        // 2. 计算总步数
        let beats = Int(timeSignature.split(separator: "/").first.map(String.init) ?? "4") ?? 4
        let totalSteps = beats * (precision / 4)
        var nameParts = Array(repeating: "", count: totalSteps)

        // 3. 遍历事件并填充名称数组
        for event in self.pattern {
            // delay 格式是 "stepIndex/precision", 所以我们直接提取 stepIndex
            if let stepIndex = Int(event.delay.split(separator: "/").first ?? "") {
                guard stepIndex < totalSteps else { continue }

                var stepString = ""
                let notes = event.notes

                // 检查是否为扫弦 (基于音符顺序)
                if let delta = event.delta, delta > 0, let firstNote = notes.first, let lastNote = notes.last {
                    if case .chordString(let firstVal) = firstNote, case .chordString(let lastVal) = lastNote {
                        if firstVal > lastVal { // 6 -> 1 is Down
                            stepString = "下"
                        } else if firstVal < lastVal { // 1 -> 6 is Up
                            stepString = "上"
                        }
                    }
                }

                // 如果不是扫弦，则为分解或和音
                if stepString.isEmpty {
                    let noteStrings = notes.map { note -> String in
                        switch note {
                        case .chordString(let stringValue):
                            return String(stringValue)
                        case .chordRoot(let rootString):
                            if rootString == "ROOT" { return "R" }
                            return rootString.replacingOccurrences(of: "-", with: "")
                        case .specificFret(_, let fret):
                            return "P\(fret)"
                        }
                    }
                    stepString = noteStrings.joined(separator: ".")
                }
                
                nameParts[stepIndex] = stepString
            }
        }

        // 4. 组合并清理
        var finalName = nameParts.joined(separator: "_")
        while finalName.hasSuffix("_") {
            finalName.removeLast()
        }
        
        return finalName
    }
}
