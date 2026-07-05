import Foundation
import Combine

/// Shared observable snapshot of the Planka structure (projects/boards/lists/labels).
/// Seeds itself from the UserDefaults cache for instant UI, then refreshes from
/// the network on demand.
@MainActor
final class PlankaData: ObservableObject {
    static let shared = PlankaData()

    @Published var projects: [PlankaProject] = []
    @Published var boards: [PlankaBoard] = []
    @Published var listsByBoard: [String: [PlankaList]] = [:]
    @Published var labelsByBoard: [String: [PlankaLabel]] = [:]
    @Published var isRefreshing = false
    @Published var lastError: String?

    private init() {
        loadFromCache()
    }

    func loadFromCache() {
        guard let cache = SettingsStore.shared.cachedStructure else { return }
        projects = cache.projects
        boards = cache.boards
        listsByBoard = cache.listsByBoard
        labelsByBoard = cache.labelsByBoard
    }

    func boards(forProject projectId: String) -> [PlankaBoard] {
        boards.filter { $0.projectId == projectId }
    }

    func lists(forBoard boardId: String) -> [PlankaList] {
        (listsByBoard[boardId] ?? [])
            .filter(\.isSelectable)
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    func labels(forBoard boardId: String) -> [PlankaLabel] {
        (labelsByBoard[boardId] ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    /// Refreshes projects + boards. Returns true on success.
    @discardableResult
    func refreshProjects() async -> Bool {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await PlankaClient.shared.fetchProjectsAndBoards()
            projects = result.projects
            boards = result.boards
            SettingsStore.shared.replaceProjectsAndBoards(projects: result.projects, boards: result.boards)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Refreshes lists + labels for one board. Returns true on success.
    @discardableResult
    func refreshBoard(_ boardId: String) async -> Bool {
        guard !boardId.isEmpty else { return false }
        do {
            let response = try await PlankaClient.shared.fetchBoard(id: boardId)
            let lists = response.included?.lists ?? []
            let labels = response.included?.labels ?? []
            listsByBoard[boardId] = lists
            labelsByBoard[boardId] = labels
            SettingsStore.shared.mergeBoardDetails(boardId: boardId, lists: lists, labels: labels)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clear() {
        projects = []
        boards = []
        listsByBoard = [:]
        labelsByBoard = [:]
        lastError = nil
    }
}
