
import SwiftUI

// MARK: - Main Views

struct GlobalSettingsView: View {
    @EnvironmentObject var appData: AppData
    @EnvironmentObject var drumPlayer: DrumPlayer
    
    var body: some View {
        HStack(spacing: 12) {
            // Key selector with shortcut badge (- / =)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "调性",
                    selection: $appData.performanceConfig.key,
                    options: appData.KEY_CYCLE
                )
                .frame(maxWidth: .infinity)

                Text("-/=")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Time signature selector with shortcut badge (T)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "拍号",
                    selection: $appData.performanceConfig.timeSignature,
                    options: appData.TIME_SIGNATURE_CYCLE
                )
                .frame(maxWidth: .infinity)

                Text("T")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Tempo card with arrow badge (↑/↓)
            ZStack(alignment: .topTrailing) {
                TempoDashboardCard(tempo: $appData.performanceConfig.tempo)
                    .frame(maxWidth: .infinity)

                Text("↑/↓")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            // Quantize selector with badge (Q)
            ZStack(alignment: .topTrailing) {
                DraggableValueCard(
                    label: "量化",
                    selection: Binding<QuantizationMode>(
                        get: { QuantizationMode(rawValue: appData.performanceConfig.quantize ?? "NONE") ?? .none },
                        set: { appData.performanceConfig.quantize = $0.rawValue }
                    ),
                    options: QuantizationMode.allCases
                )
                .frame(maxWidth: .infinity)

                Text("Q")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }

            ZStack(alignment: .topTrailing) {
                DrumMachineStatusCard()
                    .frame(maxWidth: .infinity)

                Text("P")
                    .font(.caption2).bold()
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: -8, y: 8)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Control Views

struct DashboardCardView: View {
    let label: String
    let value: String
    var unit: String? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))

            if let unit = unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

struct TempoDashboardCard: View {
    @Binding var tempo: Double
    @State private var startTempo: Double? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DashboardCardView(label: "速度", value: "\(Int(round(tempo)))", unit: "BPM")
            
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(5)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if self.startTempo == nil {
                        self.startTempo = self.tempo
                    }
                    let dragAmount = value.translation.width
                    let newTempo = self.startTempo! + Double(dragAmount / 4.0)
                    self.tempo = max(40, min(240, newTempo))
                }
                .onEnded { _ in
                    self.tempo = round(self.tempo)
                    self.startTempo = nil
                }
        )
    }
}

struct DraggableValueCard<T: Equatable & CustomStringConvertible>: View {
    let label: String
    @Binding var selection: T
    let options: [T]
    
    @State private var startIndex: Int? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DashboardCardView(label: label, value: selection.description)
            
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(5)
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard let currentIndex = options.firstIndex(of: selection) else { return }
                    if self.startIndex == nil {
                        self.startIndex = currentIndex
                    }
                    
                    let dragAmount = value.translation.width
                    let indexOffset = Int(round(dragAmount / 30.0)) // Drag sensitivity
                    
                    let newIndex = self.startIndex! + indexOffset
                    let clampedIndex = max(0, min(options.count - 1, newIndex))
                    
                    self.selection = options[clampedIndex]
                }
                .onEnded { _ in
                    self.startIndex = nil
                }
        )
    }
}

struct PlayingModeBadgeView: View {
    let playingMode: String
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(playingMode.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.15))
                    )
                
                if index < playingMode.count - 1 {
                    Text("|")
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
    }
}

struct DrumMachineStatusCard: View {
    @EnvironmentObject var drumPlayer: DrumPlayer
    @EnvironmentObject var appData: AppData

    var body: some View {
        VStack(spacing: 4) {
            Text("演奏".uppercased())
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .center, spacing: 10) {
                PlayingModeBadgeView(playingMode: appData.playingMode.shortDisplay)
                
                Text(drumPlayer.isPlaying ? "运行中" : "停止")
                    .font(.system(.title, design: .rounded).weight(.bold))
            }
            .foregroundColor(drumPlayer.isPlaying ? .green : .primary)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 60)
        .padding(8)
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            if drumPlayer.isPlaying {
                drumPlayer.stop()
            } else {
                drumPlayer.playPattern(tempo: appData.performanceConfig.tempo)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(drumPlayer.isPlaying ? Color.green : Color.secondary.opacity(0.2), lineWidth: drumPlayer.isPlaying ? 2.5 : 1)
        )
    }
}

extension QuantizationMode: CustomStringConvertible {
    public var description: String { self.displayName }
}
