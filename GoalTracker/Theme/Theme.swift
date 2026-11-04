import SwiftUI

enum Theme {
    static let gold = Color(red: 0.86, green: 0.70, blue: 0.26)
    static let goldLight = Color(red: 1.0, green: 0.87, blue: 0.50)
    static let red = Color(red: 0.90, green: 0.12, blue: 0.16)
    static let black = Color(red: 0.03, green: 0.03, blue: 0.04)

    static let goldGradient = LinearGradient(
        colors: [goldLight, gold, Color(red: 0.55, green: 0.40, blue: 0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let redGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.32, blue: 0.26), red, Color(red: 0.45, green: 0.02, blue: 0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

struct ThemedBackground: View {
    var body: some View {
        ZStack {
            Theme.black
            RadialGradient(colors: [Theme.red.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Theme.gold.opacity(0.18), .clear], center: .bottomLeading, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

/// Frosted-glass card with a gradient hairline border.
struct GlassCard<Content: View>: View {
    var accent: Color = Theme.gold
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
    }
}

struct CardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.heavy))
            .tracking(1.5)
            .foregroundStyle(Theme.gold)
    }
}

extension View {
    /// Hides the default grouped background so lists and forms sit on the themed backdrop.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(ThemedBackground())
    }
}
