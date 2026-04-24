import Foundation
import AppKit

/// Reads the shared family memory files in iCloud. Never writes them —
/// authorship lives with the Claude family-memory routing protocol, not with
/// Fort Abode. Mirrors the pattern of `WeeklyRhythmService` (iCloud path as a
/// computed property, plain file reads, no Sparkle-style version compare).
actor FamilyMemoryService {

    private let fm = FileManager.default

    // MARK: - Paths

    nonisolated private static var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// iCloud canonical for the shared family memory folder. Nonisolated so
    /// SwiftUI views can pass it to `NSWorkspace.open(_:)` without awaiting.
    nonisolated static var folderPath: String {
        "\(homePath)/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/Family Memory"
    }

    private var familyMemoryMdPath: String { "\(Self.folderPath)/FAMILY_MEMORY.md" }
    private var factsJsonPath: String { "\(Self.folderPath)/facts.json" }
    private var pdfIndexPath: String { "\(Self.folderPath)/pdf-index.md" }
    private var claudeMdPath: String { "\(Self.homePath)/.claude/CLAUDE.md" }

    // MARK: - Structured data

    /// Parse `facts.json` into the `FamilyFacts` tree. Returns nil if the file
    /// is missing or invalid — UI treats nil as "not set up yet".
    func loadFacts() async -> FamilyFacts? {
        guard fm.fileExists(atPath: factsJsonPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: factsJsonPath)) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try? decoder.decode(FamilyFacts.self, from: data)
    }

    /// Parse `FAMILY_MEMORY.md` `## Section` headers + bodies. An `isEmpty`
    /// heuristic flags sections whose body is only the italic placeholder
    /// ("_(no entries yet)_" etc.) so the UI can show a soft empty state.
    func loadSections() async -> [FamilySection] {
        guard fm.fileExists(atPath: familyMemoryMdPath),
              let content = try? String(contentsOfFile: familyMemoryMdPath, encoding: .utf8) else {
            return []
        }

        var sections: [FamilySection] = []
        var currentName: String?
        var currentBody: [String] = []

        func flush() {
            guard let name = currentName else { return }
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let isEmpty = isSectionEmpty(body: body)
            sections.append(FamilySection(
                id: name.lowercased().replacingOccurrences(of: " ", with: "-"),
                name: name,
                body: body,
                isEmpty: isEmpty
            ))
        }

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                currentName = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentBody = []
            } else if currentName != nil {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    /// Parse the `Last Modified` header from FAMILY_MEMORY.md line 2.
    /// Format: `<!-- Last Modified: 2026-04-14T17:00 by KK -->`.
    func loadLastModified() async -> String? {
        guard fm.fileExists(atPath: familyMemoryMdPath),
              let content = try? String(contentsOfFile: familyMemoryMdPath, encoding: .utf8) else {
            return nil
        }
        let pattern = "Last Modified:\\s*([^\\s]+)\\s+by\\s+([A-Z]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let lines = content.components(separatedBy: "\n").prefix(5)
        for line in lines {
            if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let timestampRange = Range(match.range(at: 1), in: line),
               let initialsRange = Range(match.range(at: 2), in: line) {
                let timestamp = String(line[timestampRange])
                let initials = String(line[initialsRange])
                return "\(timestamp) by \(initials)"
            }
        }
        return nil
    }

    // MARK: - Health

    /// Operational health rows for the Status tab. Uses `HealthCheck` so it
    /// can slot into `ComponentHealthCard` with zero adapter code.
    func healthChecks() async -> [HealthCheck] {
        let folderExists = fm.fileExists(atPath: Self.folderPath)
        let mdExists = fm.fileExists(atPath: familyMemoryMdPath)
        let factsValid = await loadFacts() != nil
        let routingInstalled = await isRoutingBlockInstalled()

        return [
            HealthCheck(
                id: "folder",
                label: "iCloud family memory folder exists",
                state: folderExists ? .granted : .missing,
                actionDeepLink: nil
            ),
            HealthCheck(
                id: "markdown",
                label: "FAMILY_MEMORY.md is readable",
                state: mdExists ? .granted : .missing,
                actionDeepLink: nil
            ),
            HealthCheck(
                id: "facts",
                label: "facts.json is valid JSON",
                state: factsValid ? .granted : .missing,
                actionDeepLink: nil
            ),
            HealthCheck(
                id: "routing",
                label: "Routing block installed in ~/.claude/CLAUDE.md",
                state: routingInstalled ? .granted : .missing,
                actionDeepLink: nil
            )
        ]
    }

    /// Detect the idempotency marker that `setup-claude-memory --family` writes
    /// into `~/.claude/CLAUDE.md`. The CLAUDE.md file may itself be a symlink
    /// into iCloud, in which case reading the resolved target is sufficient.
    private func isRoutingBlockInstalled() async -> Bool {
        guard let content = try? String(contentsOfFile: claudeMdPath, encoding: .utf8) else {
            return false
        }
        return content.contains("<!-- family-memory-routing v1 -->")
    }

    // MARK: - Actions

    /// Reveal the family memory folder in Finder. Must be @MainActor — the
    /// `NSWorkspace.shared.open(_:)` call is UI-bound.
    @MainActor
    static func revealInFinder(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Private

    /// A section body is considered "empty" if it has no meaningful content
    /// beyond italic placeholder text like `_(no entries yet)_` or
    /// `_(everything else TBD ...)_`.
    private func isSectionEmpty(body: String) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        // If after stripping italic placeholders and description lines, nothing
        // meaningful remains, treat as empty.
        let placeholder = "_(no entries yet)_"
        let simplified = trimmed
            .replacingOccurrences(of: placeholder, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if simplified.isEmpty { return true }

        // Sections with only a leading italic description paragraph and a
        // placeholder line are also effectively empty. Heuristic: if every
        // non-blank line either starts with `_` (italic) or is a known empty
        // marker, section is empty.
        let nonBlankLines = simplified
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let allItalic = nonBlankLines.allSatisfy { $0.hasPrefix("_") && $0.hasSuffix("_") }
        return allItalic
    }
}
