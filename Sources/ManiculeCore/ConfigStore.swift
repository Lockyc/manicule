import Foundation
import os

/// Reads and writes `config.json`. It never overwrites a file it couldn't take in: saving is
/// allowed only after a clean `load` (no file yet, a file that decoded, or a corrupt file
/// successfully moved aside).
public final class ConfigStore {
    private static let log = Logger(subsystem: "com.lockyc.manicule", category: "config")

    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Why saving is refused; nil once a clean `load` has run.
    public private(set) var saveRefusal: String? = "the configuration hasn't been loaded"

    public struct SaveRefused: Error, CustomStringConvertible {
        public var reason: String
        public var description: String { reason }
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The saved config, else defaults. A corrupt file is moved aside (never overwritten); a file
    /// that can't be read, or a corrupt one that can't be moved aside, leaves saving refused.
    public func load(discovered: [DiscoveredProfile]) -> Config {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            saveRefusal = nil
            return .defaults(from: discovered)
        } catch {
            refuse("\(fileURL.lastPathComponent) can't be read (\(error.localizedDescription))")
            return .defaults(from: discovered)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let config = try? decoder.decode(Config.self, from: data) {
            saveRefusal = nil
            return config
        }
        let stamp = String(Int(Date().timeIntervalSince1970))
        var aside = directory.appendingPathComponent("config.corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: aside.path) {
            aside = directory.appendingPathComponent("config.corrupt-\(stamp)-\(UUID().uuidString).json")
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            saveRefusal = nil
        } catch {
            refuse("\(fileURL.lastPathComponent) is unreadable and can't be moved aside (\(error.localizedDescription))")
        }
        return .defaults(from: discovered)
    }

    public func save(_ config: Config) throws {
        if let saveRefusal { throw SaveRefused(reason: saveRefusal) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }

    private func refuse(_ reason: String) {
        saveRefusal = reason
        Self.log.error("config won't be saved: \(reason, privacy: .public)")
    }
}
