import Foundation

/// Thin async client for the Planka 2.x REST API, with a one-shot silent
/// re-login on 401 using credentials stored in the Keychain.
final class PlankaClient {
    static let shared = PlankaClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: - URL handling

    private func baseURL() throws -> URL {
        let raw = SettingsStore.shared.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw PlankaError.notConfigured }
        var normalized = raw
        if !normalized.lowercased().hasPrefix("http://") && !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized), url.host != nil else {
            throw PlankaError.invalidURL(raw)
        }
        return url
    }

    private func endpoint(_ path: String) throws -> URL {
        try baseURL().appendingPathComponent("api").appendingPathComponent(path)
    }

    // MARK: - Auth

    /// Logs in with username/password, stores the token in the Keychain.
    @discardableResult
    func logIn(emailOrUsername: String, password: String) async throws -> String {
        let url = try endpoint("access-tokens")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "emailOrUsername": emailOrUsername,
            "password": password,
        ])
        let (data, response) = try await perform(request)
        try Self.checkStatus(response, data: data)
        guard let token = Self.extractToken(from: data) else {
            throw PlankaError.decodingFailed("login response contained no token")
        }
        try Keychain.save(key: Keychain.tokenKey, value: token)
        return token
    }

    private static func extractToken(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["item"] as? String
    }

    func logOut() {
        if let token = try? Keychain.read(key: Keychain.tokenKey) {
            // Best-effort server-side revoke; ignore failures.
            Task {
                if var request = try? await self.authorizedRequest(path: "access-tokens/me") {
                    request.httpMethod = "DELETE"
                    _ = try? await self.session.data(for: request)
                }
                _ = token
            }
        }
        Keychain.delete(key: Keychain.tokenKey)
    }

    var hasToken: Bool {
        (try? Keychain.read(key: Keychain.tokenKey)) != nil
    }

    private func authorizedRequest(path: String) async throws -> URLRequest {
        guard let token = try? Keychain.read(key: Keychain.tokenKey) else {
            throw PlankaError.notLoggedIn
        }
        var request = URLRequest(url: try endpoint(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    // MARK: - Requests with automatic re-login

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw PlankaError.network(error)
        }
    }

    /// Runs a request; on 401, silently re-logs-in once with stored credentials and retries.
    private func authorized(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        func run() async throws -> (Data, URLResponse) {
            var request = try await authorizedRequest(path: path)
            request.httpMethod = method
            if let body {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            return try await perform(request)
        }

        var (data, response) = try await run()
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // Try one silent re-login with stored credentials.
            if let user = try? Keychain.read(key: Keychain.usernameKey),
               let pass = try? Keychain.read(key: Keychain.passwordKey) {
                try await logIn(emailOrUsername: user, password: pass)
                (data, response) = try await run()
            }
        }
        try Self.checkStatus(response, data: data)
        return data
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            var message: String?
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                message = (obj["message"] as? String) ?? (obj["problems"] as? [String])?.joined(separator: ", ")
            }
            throw PlankaError.httpError(status: http.statusCode, message: message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlankaError.decodingFailed(String(describing: error))
        }
    }

    // MARK: - API surface

    /// Projects along with the boards Planka includes in the same response.
    func fetchProjectsAndBoards() async throws -> (projects: [PlankaProject], boards: [PlankaBoard]) {
        let data = try await authorized(path: "projects")
        let decoded = try decode(ProjectsResponse.self, from: data)
        let boards = (decoded.included?.boards ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        return (decoded.items, boards)
    }

    /// Lists, labels, and cards for a board.
    func fetchBoard(id: String) async throws -> BoardResponse {
        let data = try await authorized(path: "boards/\(id)")
        return try decode(BoardResponse.self, from: data)
    }

    /// A task list to attach to a freshly created card: a title plus ordered items.
    struct TaskListInput {
        let title: String
        let tasks: [String]
    }

    /// Creates a card at the bottom of the given list; optionally attaches a
    /// label, a description, and a task list with items.
    func createCard(
        listId: String,
        name: String,
        position: Double,
        labelId: String?,
        description: String? = nil,
        taskList: TaskListInput? = nil
    ) async throws -> PlankaCard {
        // Planka 2.x requires a card `type` ("project" is the standard kanban card).
        var body: [String: Any] = [
            "name": name,
            "position": position,
            "type": "project",
        ]
        if let description, !description.isEmpty {
            body["description"] = description
        }
        var data: Data
        do {
            data = try await authorized(path: "lists/\(listId)/cards", method: "POST", body: body)
        } catch PlankaError.httpError(let status, _) where status == 400 || status == 422 {
            // Fallback for servers that reject `type` (e.g. Planka 1.x).
            body.removeValue(forKey: "type")
            data = try await authorized(path: "lists/\(listId)/cards", method: "POST", body: body)
        }
        let card = try decode(ItemResponse<PlankaCard>.self, from: data).item

        if let labelId {
            do {
                _ = try await authorized(path: "cards/\(card.id)/card-labels", method: "POST", body: ["labelId": labelId])
            } catch PlankaError.httpError(let status, _) where status == 404 {
                // Planka 1.x endpoint name.
                _ = try await authorized(path: "cards/\(card.id)/labels", method: "POST", body: ["labelId": labelId])
            }
        }

        if let taskList {
            try await attachTaskList(taskList, toCard: card.id)
        }
        return card
    }

    /// Adds a task list (and its tasks) to a card. Planka 2.x nests tasks under
    /// a task list; 1.x attaches tasks directly to the card.
    private func attachTaskList(_ input: TaskListInput, toCard cardId: String) async throws {
        do {
            let listData = try await authorized(
                path: "cards/\(cardId)/task-lists", method: "POST",
                body: ["name": input.title, "position": 65536])
            let taskListId = try decode(ItemResponse<PlankaTaskList>.self, from: listData).item.id
            var position = 65536.0
            for task in input.tasks {
                _ = try await authorized(
                    path: "task-lists/\(taskListId)/tasks", method: "POST",
                    body: ["name": task, "position": position])
                position += 65536
            }
        } catch PlankaError.httpError(let status, _) where status == 404 {
            // Planka 1.x: no task lists, tasks hang off the card directly.
            var position = 65536.0
            for task in input.tasks {
                _ = try await authorized(
                    path: "cards/\(cardId)/tasks", method: "POST",
                    body: ["name": task, "position": position])
                position += 65536
            }
        }
    }
}
