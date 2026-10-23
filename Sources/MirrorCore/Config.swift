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

/// Marker that we dimmed the panel, holding the brightness to restore. A plain text file beside the
/// config, so a bundled app and a bare binary (different UserDefaults domains) share one truth.
public enum DimState {
    public static func url(besideConfig configURL: URL) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent("dimmed-brightness")
    }

    public static func load(from url: URL) -> Float? {
        (try? String(contentsOf: url, encoding: .utf8))
            .flatMap { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// `nil` removes the marker.
    public static func save(_ value: Float?, to url: URL) throws {
        guard let value else {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(value)".write(to: url, atomically: true, encoding: .utf8)
    }
}
