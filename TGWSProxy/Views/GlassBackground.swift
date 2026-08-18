import SwiftUI

/// An animated gradient backdrop behind the glass panels.
struct GlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.18),
                    Color(red: 0.10, green: 0.05, blue: 0.20),
                    Color(red: 0.02, green: 0.10, blue: 0.14),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glowing orbs for the glass effect.
            Circle()
                .fill(Color.cyan.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: animate ? 140 : -60, y: animate ? -140 : 60)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animate)

            Circle()
                .fill(Color.purple.opacity(0.30))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: animate ? -120 : 80, y: animate ? 120 : -90)
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animate)

            Circle()
                .fill(Color.teal.opacity(0.25))
                .frame(width: 180, height: 180)
                .blur(radius: 70)
                .offset(x: animate ? 30 : 150, y: animate ? -60 : 120)
                .animation(.easeInOut(duration: 7).repeatForever(autoreverses: true), value: animate)
        }
        .onAppear { animate = true }
    }
}

/// A reusable frosted-glass card with a blur effect, subtle border and shadow.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 8)
            )
    }
}

/// A stylized Telegram paper-plane logo drawn with vector shapes.
struct TelegramLogo: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Main paper-plane body.
                p.move(to: CGPoint(x: w * 0.05, y: h * 0.52))
                p.addLine(to: CGPoint(x: w * 0.95, y: h * 0.10))
                p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.93))
                p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.72))
                p.addLine(to: CGPoint(x: w * 0.40, y: h * 0.92))
                p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.62))
                p.closeSubpath()
            }
            .fill(Color.white)
            .opacity(0.95)
        }
        .aspectRatio(1.0, contentMode: .fit)
    }
}

#Preview {
    ZStack {
        GlassBackground()
        VStack(spacing: 24) {
            TelegramLogo()
                .frame(width: 64, height: 64)
                .padding(24)
                .background(
                    Circle().fill(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
            GlassCard {
                Text("Liquid Glass Card")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
}