import Foundation

/// What the tool does when a remembered external display is connected.
public enum Mode: String, Codable, CaseIterable {
    case none
    case mirror
}

public struct DisplayEntry: Codable, Equatable {
    public var name: String
    public var mode: Mode

    public init(name: String, mode: Mode) {
        self.name = name
        self.mode = mode
    }
}

/// The hand-editable config file, keyed by `vendor-model-serial`.
public struct Config: Codable, Equatable {
    public var displays: [String: DisplayEntry]

    public init(displays: [String: DisplayEntry] = [:]) {
        self.displays = displays
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/macmirrorscreen/config.json")
    }

    public static func key(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "\(vendor)-\(model)-\(serial)"
    }

    /// A missing file is an empty config; unreadable JSON throws so the caller can avoid overwriting it.
    public static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
