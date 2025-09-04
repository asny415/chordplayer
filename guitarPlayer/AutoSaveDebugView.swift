import SwiftUI

/// 自动保存功能调试视图
struct AutoSaveDebugView: View {
    @EnvironmentObject var appData: AppData
    @State private var persistenceInfo: [String: Any] = [:]
    @State private var lastUpdateTime = Date()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自动保存状态")
                .font(.headline)
                .foregroundColor(.primary)
            
            Divider()
            
            // 保存文件状态
            VStack(alignment: .leading, spacing: 8) {
                Text("保存文件状态:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(Array(persistenceInfo.keys.sorted()), id: \.self) { key in
                    if let info = persistenceInfo[key] as? [String: Any] {
                        HStack {
                            Text("• \(key):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let exists = info["exists"] as? Bool {
                                if exists {
                                    Text("已保存")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    
                                    if let size = info["size"] as? Int64 {
                                        Text("(\(formatFileSize(size)))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let modified = info["modified"] as? Date {
                                        Text("修改于: \(formatDate(modified))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("未保存")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            
            Divider()
            
            // 当前配置信息
            VStack(alignment: .leading, spacing: 8) {
                Text("当前配置:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("• 组数量: \(appData.performanceConfig.patternGroups.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 当前节拍: \(appData.performanceConfig.tempo)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 当前调性: \(appData.performanceConfig.key)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("• 当前拍号: \(appData.performanceConfig.timeSignature)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // 操作按钮
            VStack(spacing: 8) {
                Button("手动保存") {
                    appData.saveAllData()
                    updatePersistenceInfo()
                }
                .buttonStyle(.bordered)
                
                Button("重置到默认值") {
                    appData.resetToDefaults()
                    updatePersistenceInfo()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                
                Button("刷新状态") {
                    updatePersistenceInfo()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            // 最后更新时间
            Text("最后更新: \(formatDate(lastUpdateTime))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updatePersistenceInfo()
        }
    }
    
    private func updatePersistenceInfo() {
        persistenceInfo = appData.getPersistenceInfo()
        lastUpdateTime = Date()
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    AutoSaveDebugView()
        .environmentObject(AppData())
}
