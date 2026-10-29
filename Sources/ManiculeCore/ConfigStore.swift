import Foundation

public final class ConfigStore {
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("config.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Defaults when the file is missing; a corrupt file is moved aside (never overwritten) and defaults returned.
    public func load(discovered: [DiscoveredProfile]) -> Config {
        guard let data = try? Data(contentsOf: fileURL) else { return .defaults(from: discovered) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let config = try? decoder.decode(Config.self, from: data) { return config }
        let stamp = String(Int(Date().timeIntervalSince1970))
        var aside = directory.appendingPathComponent("config.corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: aside.path) {
            aside = directory.appendingPathComponent("config.corrupt-\(stamp)-\(UUID().uuidString).json")
        }
        try? FileManager.default.moveItem(at: fileURL, to: aside)
        return .defaults(from: discovered)
    }

    public func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
