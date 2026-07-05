import SwiftUI

/// Selection used for the most recently created card. Seeds the next popup so
/// burst-entering cards somewhere other than the defaults sticks between
/// openings. In-memory only: Settings defaults are untouched and win again
/// after an app relaunch.
enum LastUsedSelection {
    struct Value {
        var projectId: String
        var boardId: String
        var listId: String
        var labelId: String
    }
    static var value: Value?
}

struct NewCardView: View {
    @ObservedObject var data = PlankaData.shared

    @State private var title = ""
    @State private var projectId = LastUsedSelection.value?.projectId ?? SettingsStore.shared.defaultProjectId
    @State private var boardId = LastUsedSelection.value?.boardId ?? SettingsStore.shared.defaultBoardId
    @State private var listId = LastUsedSelection.value?.listId ?? SettingsStore.shared.defaultListId
    @State private var labelId = LastUsedSelection.value?.labelId ?? SettingsStore.shared.defaultLabelId
    @State private var errorMessage: String?
    @State private var sending = false
    @FocusState private var titleFocused: Bool

    var onDone: (_ created: Bool, _ cardName: String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Card title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($titleFocused)
                .onSubmit { submit() }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Project").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    Picker("", selection: $projectId) {
                        ForEach(data.projects) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Board").foregroundStyle(.secondary)
                    Picker("", selection: $boardId) {
                        ForEach(data.boards(forProject: projectId)) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("List").foregroundStyle(.secondary)
                    Picker("", selection: $listId) {
                        ForEach(data.lists(forBoard: boardId)) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Label").foregroundStyle(.secondary)
                    Picker("", selection: $labelId) {
                        Text("None").tag("")
                        ForEach(data.labels(forBoard: boardId)) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Text("↩ to add · ⎋ to cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                Button("Cancel") { onDone(false, nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add Card") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear {
            titleFocused = true
            // Background refresh so the dropdowns are current; cache renders instantly.
            Task {
                await data.refreshProjects()
                if !boardId.isEmpty { await data.refreshBoard(boardId) }
                validateSelections()
            }
        }
        .onChange(of: projectId) { newValue in
            boardId = data.boards(forProject: newValue).first?.id ?? ""
        }
        .onChange(of: boardId) { newValue in
            labelId = ""
            listId = data.lists(forBoard: newValue).first?.id ?? ""
            guard !newValue.isEmpty else { return }
            Task {
                await data.refreshBoard(newValue)
                if listId.isEmpty || !data.lists(forBoard: newValue).contains(where: { $0.id == listId }) {
                    listId = data.lists(forBoard: newValue).first?.id ?? ""
                }
            }
        }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !listId.isEmpty && !sending
    }

    private func validateSelections() {
        if !data.projects.isEmpty && !data.projects.contains(where: { $0.id == projectId }) {
            projectId = data.projects.first?.id ?? ""
        }
        let boards = data.boards(forProject: projectId)
        if !boards.isEmpty && !boards.contains(where: { $0.id == boardId }) {
            boardId = boards.first?.id ?? ""
        }
        let lists = data.lists(forBoard: boardId)
        if !lists.isEmpty && !lists.contains(where: { $0.id == listId }) {
            listId = lists.first?.id ?? ""
        }
        if !labelId.isEmpty && !data.labels(forBoard: boardId).contains(where: { $0.id == labelId }) {
            labelId = ""
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        errorMessage = nil
        let list = listId
        let label = labelId.isEmpty ? nil : labelId
        Task {
            do {
                // Position per setting: top = half the minimum existing position,
                // bottom = max + one gap. Planka reindexes on collisions.
                let response = try await PlankaClient.shared.fetchBoard(id: boardId)
                let positions = (response.included?.cards ?? [])
                    .filter { $0.listId == list }
                    .compactMap(\.position)
                let position: Double
                if SettingsStore.shared.newCardsAtTop {
                    position = (positions.min() ?? 131072) / 2
                } else {
                    position = (positions.max() ?? 0) + 65536
                }
                _ = try await PlankaClient.shared.createCard(
                    listId: list, name: name, position: position, labelId: label)
                LastUsedSelection.value = .init(
                    projectId: projectId, boardId: boardId, listId: listId, labelId: labelId)
                sending = false
                onDone(true, name)
            } catch {
                sending = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
