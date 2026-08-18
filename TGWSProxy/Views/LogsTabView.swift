чimport SwiftUI

/// The logs tab: real-time streaming log view with level filtering,
/// auto-scroll, and a clear button.
struct LogsTabView: View {
    @ObservedObject private var logStore = LogStore.shared
    @State private var filter: LogEntry.Level? = nil
    @State private var autoScroll = true
    @State private var textContent = ""
    @State private var contentDirty = false

    var body: some View {
        VStack(spacing: 12) {
            filterBar
            logView
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onReceive(logStore.$entries) { _ in
            rebuildText()
        }
        .onAppear {
            rebuildText()
        }
    }

    private var filteredLogs: [LogEntry] {
        guard let filter else { return logStore.entries }
        return logStore.entries.filter { $0.level == filter }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 8) {
                filterButton(.info, title: "Info")
                filterButton(.warning, title: "Warn")
                filterButton(.error, title: "Error")

                Spacer()

                Button {
                    logStore.clear()
                    rebuildText()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filterButton(_ level: LogEntry.Level, title: String) -> some View {
        let isActive = filter == level
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                filter = isActive ? nil : level
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: level.systemImage)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(isActive ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isActive ? level.tintColor.opacity(0.7) : .white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log content

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(textContent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("logText")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .onChange(of: textContent) { _ in
                if autoScroll {
                    withAnimation {
                        proxy.scrollTo("logText", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Build text

    private func rebuildText() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let lines = filteredLogs.map { entry in
            let time = formatter.string(from: entry.timestamp)
            let levelTag: String
            switch entry.level {
            case .error: levelTag = "ERR "
            case .warning: levelTag = "WARN"
            case .debug: levelTag = "DBG "
            case .info: levelTag = "INFO"
            }
            return "\(time) [\(levelTag)] \(entry.message)"
        }
        textContent = lines.joined(separator: "\n")
    }
}

private extension LogEntry.Level {
    var tintColor: Color {
        switch self {
        case .info: return .teal
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }
}