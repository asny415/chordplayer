import SwiftUI

struct EmptyStateView: View {
    let imageName: String
    let text: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: imageName)
                    .font(.title)
                    .foregroundColor(.secondary)

                Text(text)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Material.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#if DEBUG
struct EmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview in a grid to simulate the real dashboard layout
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
            EmptyStateView(
                imageName: "music.quarternote.3",
                text: "创建鼓模式",
                action: { print("Action!") }
            )
            EmptyStateView(
                imageName: "guitars",
                text: "添加和弦进行",
                action: { print("Action!") }
            )
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
#endif
