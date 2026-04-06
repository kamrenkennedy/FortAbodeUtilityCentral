import Foundation

/// Validates tokens and credentials remotely during setup wizard flows.
actor SetupValidationService {

    // MARK: - Notion Token Validation

    /// Validates a Notion integration token by calling the Notion API.
    /// Returns the workspace owner's name on success.
    func validateNotionToken(_ token: String) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("ntn_") || trimmed.hasPrefix("secret_") else {
            throw SetupValidationError.invalidFormat("Token should start with ntn_ or secret_")
        }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/users/me")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SetupValidationError.networkError("Can't reach Notion — check your internet connection")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SetupValidationError.networkError("Unexpected response from Notion")
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseNotionUserName(from: data)
        case 401:
            throw SetupValidationError.invalidToken("Invalid token — double-check you copied the full secret")
        case 403:
            throw SetupValidationError.insufficientPermissions("Token lacks required permissions")
        default:
            throw SetupValidationError.networkError("Notion returned status \(httpResponse.statusCode)")
        }
    }

    // MARK: - Private

    private func parseNotionUserName(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String, !name.isEmpty else {
            // Fall back to bot owner name for integration tokens
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bot = json["bot"] as? [String: Any],
               let owner = bot["owner"] as? [String: Any],
               let user = owner["user"] as? [String: Any],
               let ownerName = user["name"] as? String {
                return ownerName
            }
            return "Notion Workspace"
        }
        return name
    }
}

// MARK: - Errors

enum SetupValidationError: LocalizedError {
    case invalidFormat(String)
    case invalidToken(String)
    case insufficientPermissions(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg),
             .invalidToken(let msg),
             .insufficientPermissions(let msg),
             .networkError(let msg):
            return msg
        }
    }
}
