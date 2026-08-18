import SwiftUI

/// The main window with the Liquid Glass design and a floating tab bar
/// for Proxy, Settings, and Logs.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            GlassBackground()

            VStack(spacing: 0) {
                // Header
                header

                // Tab content
                ZStack {
                    switch appState.selectedTab {
                    case .proxy:
                        ProxyTabView()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .settings:
                        SettingsTabView()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .logs:
                        LogsTabView()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.25), value: appState.selectedTab)

                // Floating tab bar
                GlassTabBar(selection: $appState.selectedTab)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TG WS Proxy")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(appState.selectedTab.title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let running = appState.proxyManager.isListening
        HStack(spacing: 8) {
            Circle()
                .fill(running ? Color.green : Color.red)
                .frame(width: 10, height: 10)
                .shadow(color: (running ? Color.green : Color.red).opacity(0.8), radius: 6)
            Text(running ? "Активен" : "Остановлен")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
    }
}

/// The floating liquid-glass tab bar.
struct GlassTabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack {
            ForEach(Tab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        )
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.8), Color.blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(.clear)
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.5) : .clear, radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}