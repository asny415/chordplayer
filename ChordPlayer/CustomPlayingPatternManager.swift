
import Foundation
import Combine

/// 自定义演奏模式管理器
class CustomPlayingPatternManager: ObservableObject {
    static let shared = CustomPlayingPatternManager()
    
    @Published var customPlayingPatterns: PatternLibrary = [:]
    
    private let customPatternsFile: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 设置文件路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let chordPlayerDirectory = documentsPath.appendingPathComponent("ChordPlayer")
        customPatternsFile = chordPlayerDirectory.appendingPathComponent("custom_patterns.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: chordPlayerDirectory, withIntermediateDirectories: true)
        
        // 加载
        loadCustomPatterns()
        
        // 监听变化并自动保存
        $customPlayingPatterns
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveCustomPatterns()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据操作
    
    func loadCustomPatterns() {
        guard FileManager.default.fileExists(atPath: customPatternsFile.path) else {
            print("[CustomPlayingPatternManager] Custom patterns file not found, starting with empty library")
            return
        }
        
        do {
            let data = try Data(contentsOf: customPatternsFile)
            let decoder = JSONDecoder()
            customPlayingPatterns = try decoder.decode(PatternLibrary.self, from: data)
            print("[CustomPlayingPatternManager] ✅ Loaded custom playing patterns")
        } catch {
            print("[CustomPlayingPatternManager] ❌ Failed to load custom playing patterns: \(error)")
            customPlayingPatterns = [:]
        }
    }
    
    func saveCustomPatterns() {
        do {
            let encoder = JSONEncoder()
            // Avoid escaping forward slashes (so delays like "1/4" are written as-is)
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(customPlayingPatterns)
            try data.write(to: customPatternsFile)
            print("[CustomPlayingPatternManager] ✅ Saved custom playing patterns")
        } catch {
            print("[CustomPlayingPatternManager] ❌ Failed to save custom playing patterns: \(error)")
        }
    }
    
    /// 添加或更新自定义演奏模式
    func addOrUpdatePattern(pattern: GuitarPattern, timeSignature: String) {
        if customPlayingPatterns[timeSignature] == nil {
            customPlayingPatterns[timeSignature] = []
        }
        
        if let index = customPlayingPatterns[timeSignature]?.firstIndex(where: { $0.id == pattern.id }) {
            customPlayingPatterns[timeSignature]?[index] = pattern
            print("[CustomPlayingPatternManager] ✅ Updated custom playing pattern: \(pattern.id) in \(timeSignature)")
        } else {
            customPlayingPatterns[timeSignature]?.append(pattern)
            print("[CustomPlayingPatternManager] ✅ Added custom playing pattern: \(pattern.id) in \(timeSignature)")
        }
    }
    
    /// 删除自定义演奏模式
    func deletePattern(id: String, timeSignature: String) {
        customPlayingPatterns[timeSignature]?.removeAll(where: { $0.id == id })
        if customPlayingPatterns[timeSignature]?.isEmpty == true {
            customPlayingPatterns.removeValue(forKey: timeSignature)
        }
        print("[CustomPlayingPatternManager] ✅ Deleted custom playing pattern: \(id) from \(timeSignature)")
    }
    
    /// 检查演奏模式是否存在
    func patternExists(id: String, timeSignature: String) -> Bool {
        return customPlayingPatterns[timeSignature]?.contains(where: { $0.id == id }) ?? false
    }
    
    /// 合并内置和自定义演奏模式
    func combinedPatternLibrary(with builtInPatterns: PatternLibrary) -> PatternLibrary {
        var combined = builtInPatterns
        for (timeSig, patterns) in customPlayingPatterns {
            if combined[timeSig] == nil {
                combined[timeSig] = []
            }
            // To avoid duplicates, we can remove built-in patterns that have the same ID as custom ones.
            let customIDs = Set(patterns.map { $0.id })
            combined[timeSig]?.removeAll(where: { customIDs.contains($0.id) })
            combined[timeSig]?.append(contentsOf: patterns)
        }
        return combined
    }
}
