import Foundation
import Combine

/// 自定义和弦管理器
class CustomChordManager: ObservableObject {
    static let shared = CustomChordManager()
    
    @Published var customChords: CustomChordLibrary = [:]
    
    private let customChordsFile: URL
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // 设置自定义和弦文件路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let chordPlayerDirectory = documentsPath.appendingPathComponent("ChordPlayer")
        customChordsFile = chordPlayerDirectory.appendingPathComponent("custom_chords.json")
        
        // 确保目录存在
        try? FileManager.default.createDirectory(at: chordPlayerDirectory, withIntermediateDirectories: true)
        
        // 加载自定义和弦
        loadCustomChords()
        
        // 监听自定义和弦变化并自动保存
        $customChords
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveCustomChords()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 数据操作
    
    /// 加载自定义和弦
    func loadCustomChords() {
        guard FileManager.default.fileExists(atPath: customChordsFile.path) else {
            print("[CustomChordManager] Custom chords file not found, starting with empty library")
            return
        }
        
        do {
            let data = try Data(contentsOf: customChordsFile)
            let decoder = JSONDecoder()
            customChords = try decoder.decode(CustomChordLibrary.self, from: data)
            print("[CustomChordManager] ✅ Loaded \(customChords.count) custom chords")
        } catch {
            print("[CustomChordManager] ❌ Failed to load custom chords: \(error)")
            customChords = [:]
        }
    }
    
    /// 保存自定义和弦
    func saveCustomChords() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(customChords)
            try data.write(to: customChordsFile)
            print("[CustomChordManager] ✅ Saved \(customChords.count) custom chords")
        } catch {
            print("[CustomChordManager] ❌ Failed to save custom chords: \(error)")
        }
    }
    
    /// 添加自定义和弦
    func addChord(name: String, fingering: [StringOrInt]) {
        customChords[name] = fingering
        print("[CustomChordManager] ✅ Added custom chord: \(name)")
    }
    
    /// 更新自定义和弦
    func updateChord(name: String, fingering: [StringOrInt]) {
        customChords[name] = fingering
        print("[CustomChordManager] ✅ Updated custom chord: \(name)")
    }
    
    /// 删除自定义和弦
    func deleteChord(name: String) {
        customChords.removeValue(forKey: name)
        print("[CustomChordManager] ✅ Deleted custom chord: \(name)")
    }
    
    /// 检查和弦是否存在
    func chordExists(name: String) -> Bool {
        return customChords[name] != nil
    }
    
    /// 获取所有自定义和弦名称
    var customChordNames: [String] {
        return Array(customChords.keys).sorted()
    }
    
    /// 合并内置和弦和自定义和弦
    func combinedChordLibrary(with builtInChords: ChordLibrary) -> ChordLibrary {
        var combined = builtInChords
        for (key, value) in customChords {
            combined[key] = value
        }
        return combined
    }
}

// MARK: - 类型别名
typealias CustomChordLibrary = [String: [StringOrInt]]
