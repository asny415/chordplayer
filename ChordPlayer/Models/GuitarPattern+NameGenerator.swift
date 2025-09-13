
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
            if let stepIndex = Int(event.delay.split(separator: "/").first ?? "") {
                guard stepIndex < totalSteps else { continue }

                var stepString = ""

                // 检查是否为扫弦
                if event.delta != nil {
                    let stringValues = event.notes.compactMap { note -> Int? in
                        if case .chordString(let v) = note { return v }
                        return nil
                    }

                    if let firstVal = stringValues.first, let lastVal = stringValues.last {
                        let isFullStrum = stringValues.count == 6

                        if firstVal > lastVal { // 物理下扫 (e.g., 6 -> 1), 命名为 "上"
                            if isFullStrum {
                                stepString = "上"
                            } else {
                                if firstVal == 6 {
                                    stepString = "上\(lastVal)"
                                } else if lastVal == 1 {
                                    stepString = "\(firstVal)上"
                                } else {
                                    stepString = "\(firstVal)上\(lastVal)"
                                }
                            }
                        } else if firstVal < lastVal { // 物理上扫 (e.g., 1 -> 6), 命名为 "下"
                            if isFullStrum {
                                stepString = "下"
                            } else {
                                if firstVal == 1 {
                                    stepString = "下\(lastVal)"
                                } else if lastVal == 6 {
                                    stepString = "\(firstVal)下"
                                } else {
                                    stepString = "\(firstVal)下\(lastVal)"
                                }
                            }
                        }
                    }
                }

                // 如果不是扫弦或扫弦命名失败，则为分解或和音
                if stepString.isEmpty {
                    let noteStrings = event.notes.map { note -> String in
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
        
        return finalName.isEmpty ? "新模式" : finalName
    }
}
