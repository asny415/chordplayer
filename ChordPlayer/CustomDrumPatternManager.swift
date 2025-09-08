
import Foundation
import Combine

/// 自定义鼓点模式管理器
class CustomDrumPatternManager: ObservableObject {
    static let shared = CustomDrumPatternManager()
    
    @Published var customDrumPatterns: DrumPatternLibrary = [:]
    
    private let customPatternsFile: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 设置文件路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let chordPlayerDirectory = documentsPath.appendingPathComponent("ChordPlayer")
        customPatternsFile = chordPlayerDirectory.appendingPathComponent("custom_drums.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: chordPlayerDirectory, withIntermediateDirectories: true)
        
        // 加载
        loadCustomPatterns()
        
        // 监听变化并自动保存
        $customDrumPatterns
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveCustomPatterns()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据操作
    
    func loadCustomPatterns() {
        guard FileManager.default.fileExists(atPath: customPatternsFile.path) else {
            print("[CustomDrumPatternManager] Custom drums file not found, starting with empty library")
            return
        }
        
        do {
            let data = try Data(contentsOf: customPatternsFile)
            let decoder = JSONDecoder()
            customDrumPatterns = try decoder.decode(DrumPatternLibrary.self, from: data)
            print("[CustomDrumPatternManager] ✅ Loaded custom drum patterns")
        } catch {
            print("[CustomDrumPatternManager] ❌ Failed to load custom drum patterns: \(error)")
            customDrumPatterns = [:]
        }
    }
    
    func saveCustomPatterns() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(customDrumPatterns)
            try data.write(to: customPatternsFile)
            print("[CustomDrumPatternManager] ✅ Saved custom drum patterns")
        } catch {
            print("[CustomDrumPatternManager] ❌ Failed to save custom drum patterns: \(error)")
        }
    }
    
    /// 添加或更新自定义鼓点模式
    func addOrUpdatePattern(id: String, timeSignature: String, pattern: DrumPattern) {
        if customDrumPatterns[timeSignature] == nil {
            customDrumPatterns[timeSignature] = [:]
        }
        customDrumPatterns[timeSignature]?[id] = pattern
        print("[CustomDrumPatternManager] ✅ Added/Updated custom drum pattern: \(id) in \(timeSignature)")
    }
    
    /// 删除自定义鼓点模式
    func deletePattern(id: String, timeSignature: String) {
        customDrumPatterns[timeSignature]?.removeValue(forKey: id)
        if customDrumPatterns[timeSignature]?.isEmpty == true {
            customDrumPatterns.removeValue(forKey: timeSignature)
        }
        print("[CustomDrumPatternManager] ✅ Deleted custom drum pattern: \(id) from \(timeSignature)")
    }
    
    /// 检查鼓点模式是否存在
    func patternExists(id: String, timeSignature: String) -> Bool {
        return customDrumPatterns[timeSignature]?[id] != nil
    }
    
    /// 合并内置和自定义鼓点模式
    func combinedDrumLibrary(with builtInPatterns: DrumPatternLibrary) -> DrumPatternLibrary {
        var combined = builtInPatterns
        for (timeSig, patterns) in customDrumPatterns {
            if combined[timeSig] == nil {
                combined[timeSig] = [:]
            }
            for (id, pattern) in patterns {
                combined[timeSig]?[id] = pattern
            }
        }
        return combined
    }
}
