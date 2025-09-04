import Foundation
import Combine

/// 数据持久化管理器，负责自动保存和加载应用数据
class DataPersistenceManager: ObservableObject {
    static let shared = DataPersistenceManager()
    
    // 文件路径
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let performanceConfigURL: URL
    private let appConfigURL: URL
    
    // 自动保存相关
    private var saveTimer: Timer?
    private let saveDelay: TimeInterval = 2.0 // 2秒延迟保存
    private var pendingSave = false
    
    // Combine
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        performanceConfigURL = documentsDirectory.appendingPathComponent("performance_config.json")
        appConfigURL = documentsDirectory.appendingPathComponent("app_config.json")
        
        print("[DataPersistenceManager] Documents directory: \(documentsDirectory.path)")
        print("[DataPersistenceManager] Performance config URL: \(performanceConfigURL.path)")
        print("[DataPersistenceManager] App config URL: \(appConfigURL.path)")
    }
    
    // MARK: - 保存方法
    
    /// 保存性能配置
    func savePerformanceConfig(_ config: PerformanceConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: performanceConfigURL)
            print("[DataPersistenceManager] ✅ Performance config saved successfully")
        } catch {
            print("[DataPersistenceManager] ❌ Failed to save performance config: \(error)")
        }
    }
    
    /// 保存应用配置
    func saveAppConfig(_ config: AppConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: appConfigURL)
            print("[DataPersistenceManager] ✅ App config saved successfully")
        } catch {
            print("[DataPersistenceManager] ❌ Failed to save app config: \(error)")
        }
    }
    
    /// 延迟保存性能配置（防抖）
    func schedulePerformanceConfigSave(_ config: PerformanceConfig) {
        pendingSave = true
        
        // 取消之前的定时器
        saveTimer?.invalidate()
        
        // 设置新的定时器
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.pendingSave else { return }
            self.savePerformanceConfig(config)
            self.pendingSave = false
        }
    }
    
    // MARK: - 加载方法
    
    /// 加载性能配置
    func loadPerformanceConfig() -> PerformanceConfig? {
        guard FileManager.default.fileExists(atPath: performanceConfigURL.path) else {
            print("[DataPersistenceManager] No saved performance config found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: performanceConfigURL)
            let config = try JSONDecoder().decode(PerformanceConfig.self, from: data)
            print("[DataPersistenceManager] ✅ Performance config loaded successfully")
            return config
        } catch {
            print("[DataPersistenceManager] ❌ Failed to load performance config: \(error)")
            return nil
        }
    }
    
    /// 加载应用配置
    func loadAppConfig() -> AppConfig? {
        guard FileManager.default.fileExists(atPath: appConfigURL.path) else {
            print("[DataPersistenceManager] No saved app config found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: appConfigURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            print("[DataPersistenceManager] ✅ App config loaded successfully")
            return config
        } catch {
            print("[DataPersistenceManager] ❌ Failed to load app config: \(error)")
            return nil
        }
    }
    
    // MARK: - 清理方法
    
    /// 清理保存的定时器
    func cleanup() {
        saveTimer?.invalidate()
        saveTimer = nil
        
        // 如果有待保存的数据，立即保存
        if pendingSave {
            print("[DataPersistenceManager] Saving pending data before cleanup...")
            // 这里需要从外部传入当前配置，因为这里没有引用
        }
    }
    
    /// 删除所有保存的数据（用于重置）
    func clearAllData() {
        do {
            if FileManager.default.fileExists(atPath: performanceConfigURL.path) {
                try FileManager.default.removeItem(at: performanceConfigURL)
                print("[DataPersistenceManager] ✅ Performance config cleared")
            }
            if FileManager.default.fileExists(atPath: appConfigURL.path) {
                try FileManager.default.removeItem(at: appConfigURL)
                print("[DataPersistenceManager] ✅ App config cleared")
            }
        } catch {
            print("[DataPersistenceManager] ❌ Failed to clear data: \(error)")
        }
    }
    
    // MARK: - 调试方法
    
    /// 获取保存文件的信息
    func getSavedFilesInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        if FileManager.default.fileExists(atPath: performanceConfigURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: performanceConfigURL.path)
                info["performance_config"] = [
                    "exists": true,
                    "size": (attributes[.size] as? Int64) ?? 0 as Any,
                    "modified": (attributes[.modificationDate] as? Date) ?? Date() as Any
                ]
            } catch {
                info["performance_config"] = ["exists": true, "error": error.localizedDescription]
            }
        } else {
            info["performance_config"] = ["exists": false]
        }
        
        if FileManager.default.fileExists(atPath: appConfigURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: appConfigURL.path)
                info["app_config"] = [
                    "exists": true,
                    "size": (attributes[.size] as? Int64) ?? 0 as Any,
                    "modified": (attributes[.modificationDate] as? Date) ?? Date() as Any
                ]
            } catch {
                info["app_config"] = ["exists": true, "error": error.localizedDescription]
            }
        } else {
            info["app_config"] = ["exists": false]
        }
        
        return info
    }
}
