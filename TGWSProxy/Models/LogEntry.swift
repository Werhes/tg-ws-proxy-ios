import Foundation

/// A single log line produced by the proxy engine.
struct LogEntry: Identifiable, Equatable {
    enum Level: String, Equatable {
        case info
        case warning
        case error
        case debug

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            case .debug: return "hammer"
            }
        }

        var tint: String {
            switch self {
            case .info: return "teal"
            case .warning: return "orange"
            case .error: return "red"
            case .debug: return "gray"
            }
        }
    }

    let id: UUID
    let timestamp: Date
    let level: Level
    let message: String

    init(level: Level, message: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// A thread-safe log buffer shared between the engine and the Logs tab.
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 2000
    private let lock = NSLock()

    private init() {}

    func append(_ level: LogEntry.Level, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    var latest: [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

/// Convenience functions to log from anywhere in the engine.
enum Log {
    static func info(_ message: String) { LogStore.shared.append(.info, message) }
    static func warning(_ message: String) { LogStore.shared.append(.warning, message) }
    static func error(_ message: String) { LogStore.shared.append(.error, message) }
    static func debug(_ message: String) { LogStore.shared.append(.debug, message) }
}