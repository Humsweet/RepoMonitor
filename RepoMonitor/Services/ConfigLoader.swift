import Foundation

enum ConfigLoader {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Config Path Resolution

    static func resolveConfigDir() -> URL {
        // 1. Environment variable
        if let envPath = ProcessInfo.processInfo.environment["REPO_MONITOR_CONFIG"],
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath).deletingLastPathComponent()
        }

        // 2. ~/.config/repo-monitor/
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("repo-monitor")
        return configDir
    }

    static func configFilePath() -> URL {
        resolveConfigDir().appendingPathComponent("config.json")
    }

    static func stateFilePath(from config: MonitorConfig) -> URL {
        let statePath = config.state.filePath
        if statePath.hasPrefix("/") {
            return URL(fileURLWithPath: statePath)
        }
        return resolveConfigDir().appendingPathComponent(statePath)
    }

    static func logFilePath(from config: MonitorConfig) -> URL {
        let logPath = config.logging.filePath
        if logPath.hasPrefix("/") {
            return URL(fileURLWithPath: logPath)
        }
        return resolveConfigDir().appendingPathComponent(logPath)
    }

    // MARK: - Config Load/Save

    static func loadConfig() throws -> MonitorConfig {
        let path = configFilePath()
        guard FileManager.default.fileExists(atPath: path.path) else {
            return MonitorConfig.defaultConfig
        }
        let data = try Data(contentsOf: path)
        return try decoder.decode(MonitorConfig.self, from: data)
    }

    static func saveConfig(_ config: MonitorConfig) throws {
        let path = configFilePath()
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: path, options: .atomic)
    }

    // MARK: - State Load/Save

    static func loadState(from config: MonitorConfig) -> PersistedState {
        let path = stateFilePath(from: config)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return PersistedState(repos: [])
        }
        return state
    }

    static func saveState(_ state: PersistedState, config: MonitorConfig) {
        let path = stateFilePath(from: config)
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: path, options: .atomic)
    }

    // MARK: - Create Default Config

    static func createDefaultConfigIfNeeded() {
        let path = configFilePath()
        guard !FileManager.default.fileExists(atPath: path.path) else { return }
        try? saveConfig(MonitorConfig.defaultConfig)
    }
}
