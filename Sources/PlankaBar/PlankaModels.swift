import Foundation

// MARK: - Planka 2.x API models
// Planka sends entity ids as JSON strings. Responses are shaped as
// { "item": ... } or { "items": [...], "included": { ... } }.

struct PlankaProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct PlankaBoard: Codable, Identifiable, Hashable {
    let id: String
    let projectId: String
    let name: String
    let position: Double?
}

struct PlankaList: Codable, Identifiable, Hashable {
    let id: String
    let boardId: String
    let name: String?
    let position: Double?
    /// Planka 2.x list types: "active", "closed", plus system "archive"/"trash".
    let type: String?

    var isSelectable: Bool {
        guard let type else { return true } // 1.x boards have no type
        return type == "active" || type == "closed"
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return type?.capitalized ?? "Untitled"
    }
}

struct PlankaLabel: Codable, Identifiable, Hashable {
    let id: String
    let boardId: String
    let name: String?
    let color: String?
    let position: Double?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return color?.replacingOccurrences(of: "-", with: " ").capitalized ?? "Label"
    }
}

struct PlankaCard: Codable, Identifiable, Hashable {
    let id: String
    let listId: String?
    let name: String?
    let position: Double?
}

struct PlankaTaskList: Codable, Identifiable, Hashable {
    let id: String
    let cardId: String?
    let name: String?
    let position: Double?
}

// MARK: - Response envelopes

struct ItemResponse<T: Codable>: Codable {
    let item: T
}

struct ProjectsResponse: Codable {
    struct Included: Codable {
        let boards: [PlankaBoard]?
    }
    let items: [PlankaProject]
    let included: Included?
}

struct BoardResponse: Codable {
    struct Included: Codable {
        let lists: [PlankaList]?
        let labels: [PlankaLabel]?
        let cards: [PlankaCard]?
    }
    let item: PlankaBoard
    let included: Included?
}

// MARK: - Errors

enum PlankaError: LocalizedError {
    case notConfigured
    case invalidURL(String)
    case notLoggedIn
    case httpError(status: Int, message: String?)
    case decodingFailed(String)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Planka is not configured yet. Open Settings and log in."
        case .invalidURL(let url):
            return "\"\(url)\" is not a valid Planka URL."
        case .notLoggedIn:
            return "Not logged in to Planka. Open Settings and log in."
        case .httpError(let status, let message):
            if let message, !message.isEmpty {
                return "Planka returned an error (\(status)): \(message)"
            }
            switch status {
            case 401: return "Session expired or invalid credentials (401)."
            case 403: return "You don't have permission for that (403)."
            case 404: return "Not found on the server (404) — the project/board may have been deleted."
            default: return "Planka returned HTTP \(status)."
            }
        case .decodingFailed(let detail):
            return "Unexpected response from Planka: \(detail)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
