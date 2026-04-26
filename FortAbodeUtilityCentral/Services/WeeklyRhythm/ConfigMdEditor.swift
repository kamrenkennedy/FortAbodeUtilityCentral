import Foundation

// Surgical edits to the user-owned `{user}/config.md`. The engine spec marks
// config.md as "User-owned. Never overwritten by updates." (engine-spec.md
// §1) so every write here MUST be section-scoped — replace one weekday line
// inside the `## Day Types` section, never rewrite the whole file. If the
// expected structure isn't found, the editor logs and refuses to write
// rather than risk corrupting the user's hand-edits.
//
// Phase 5b scope note: writes the canonical `WRDayType.label` ("Make",
// "Move", "Recover", "Admin", "Open") to config.md. If the user has a custom
// label like "Creative" or "Business Dev" in that slot, the edit overwrites
// it. Custom-label preservation requires reading the engine's structured
// `day_types:` array first — Phase 5d concern.

public actor ConfigMdEditor {

    public init() {}

    /// Replace the value of one weekday line inside the `## Day Types`
    /// section of `config.md`. Returns true on success; false (with a logged
    /// reason) if the section can't be located, the weekday line is missing,
    /// or the write fails. The file is left untouched on any failure.
    ///
    /// `weekdayName`: full English name — "Sunday", "Monday", … "Saturday".
    public func updateDayType(
        weekdayName: String,
        newType: WRDayType,
        configPath: String
    ) async -> Bool {
        guard Self.isValidWeekdayName(weekdayName) else {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.ConfigMd",
                message: "invalid weekday name",
                context: ["weekdayName": weekdayName]
            )
            return false
        }

        let url = URL(fileURLWithPath: configPath)
        let original: String
        do {
            original = try String(contentsOf: url, encoding: .utf8)
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.ConfigMd",
                message: "could not read config.md",
                context: ["path": configPath, "error": "\(error)"]
            )
            return false
        }

        let lines = original.components(separatedBy: "\n")
        var updatedLines: [String] = []
        updatedLines.reserveCapacity(lines.count)

        var inSection = false
        var found = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Enter section
            if trimmed == "## Day Types" {
                inSection = true
                updatedLines.append(line)
                continue
            }

            // Exit section on next heading
            if inSection && trimmed.hasPrefix("## ") {
                inSection = false
            }

            // Replace matching weekday line within the section. Match the
            // weekday name at the start (after optional whitespace), case
            // insensitive, followed by `:` and arbitrary value.
            if inSection,
               line.range(of: "^\\s*\(weekdayName)\\s*:", options: [.regularExpression, .caseInsensitive]) != nil {
                updatedLines.append("\(weekdayName): \(newType.label)")
                found = true
                continue
            }

            updatedLines.append(line)
        }

        guard found else {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.ConfigMd",
                message: "day-type entry not found in `## Day Types` section",
                context: ["weekday": weekdayName, "path": configPath]
            )
            return false
        }

        let updated = updatedLines.joined(separator: "\n")
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            await ErrorLogger.shared.log(
                area: "WeeklyRhythm.ConfigMd",
                message: "failed to write config.md",
                context: ["path": configPath, "error": "\(error)"]
            )
            return false
        }
    }

    private static let validWeekdayNames: Set<String> = [
        "Sunday", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday"
    ]

    private static func isValidWeekdayName(_ name: String) -> Bool {
        validWeekdayNames.contains(name)
    }
}
