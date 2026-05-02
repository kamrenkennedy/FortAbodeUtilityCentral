import Foundation

// App-local UI state that the engine has no concept of — currently just
// errand sort order. Lives in `~/Library/Application Support/
// FortAbodeUtilityCentral/weekly-rhythm-ui-state.json` so it doesn't pollute
// iCloud. State is keyed by week-anchor ISO date (Monday) so reordering one
// week doesn't bleed into another.
//
// Engine-bound mutations (errand done, event move, proposal accept/decline)
// go to `PendingMutationsStore` instead. Errand sort order is purely UI:
// when the engine regenerates the dashboard, it has no opinion on which
// errand should appear first; the user's chosen order should survive across
// runs without round-tripping through the engine.

public actor WeeklyRhythmUIStateStore {

    public struct WeekUIState: Codable, Equatable, Sendable {
        public var errandOrder: [String]

        public init(errandOrder: [String] = []) {
            self.errandOrder = errandOrder
        }
    }

    public struct UIStateBundle: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var perWeek: [String: WeekUIState]

        public init(schemaVersion: Int = 1, perWeek: [String: WeekUIState] = [:]) {
            self.schemaVersion = schemaVersion
            self.perWeek = perWeek
        }
    }

    public init() {}

    /// Read the bundle. Empty-bundle is the default for a fresh install.
    public func read() async -> UIStateBundle {
        guard let path = Self.fileURL()?.path,
              FileManager.default.fileExists(atPath: path) else {
            return UIStateBundle()
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(UIStateBundle.self, from: data)
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.UIState",
                message: "failed to decode UI state, falling back to empty",
                context: ["path": path, "error": "\(error)"]
            )
            return UIStateBundle()
        }
    }

    /// Read the per-week state for `weekISODate`. Empty if no state exists.
    public func read(weekISODate: String) async -> WeekUIState {
        let bundle = await read()
        return bundle.perWeek[weekISODate] ?? WeekUIState()
    }

    /// Replace one week's state. Reads the bundle, swaps the entry, writes
    /// back atomically. Returns true on success.
    public func write(_ state: WeekUIState, weekISODate: String) async -> Bool {
        var bundle = await read()
        bundle.perWeek[weekISODate] = state
        return await write(bundle: bundle)
    }

    /// Write the full bundle atomically.
    public func write(bundle: UIStateBundle) async -> Bool {
        guard let url = Self.fileURL() else {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.UIState",
                message: "could not resolve Application Support directory"
            )
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.UIState",
                message: "failed to write UI state",
                context: ["path": url.path, "error": "\(error)"]
            )
            return false
        }
    }

    // MARK: - File path

    private static func fileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return appSupport
            .appendingPathComponent("FortAbodeUtilityCentral", isDirectory: true)
            .appendingPathComponent("weekly-rhythm-ui-state.json")
    }
}
