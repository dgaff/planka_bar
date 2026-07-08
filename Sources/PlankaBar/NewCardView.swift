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

/// The text inputs that Tab cycles through: Title → Description → Task List →
/// back to Title. Pickers are deliberately excluded so burst entry stays on the
/// keyboard (Doug's speed use case).
enum CardField: Hashable {
    case title, description, taskList
}

struct NewCardView: View {
    @ObservedObject var data = PlankaData.shared

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var taskListText = ""
    @State private var projectId = LastUsedSelection.value?.projectId ?? SettingsStore.shared.defaultProjectId
    @State private var boardId = LastUsedSelection.value?.boardId ?? SettingsStore.shared.defaultBoardId
    @State private var listId = LastUsedSelection.value?.listId ?? SettingsStore.shared.defaultListId
    @State private var labelId = LastUsedSelection.value?.labelId ?? SettingsStore.shared.defaultLabelId
    @State private var errorMessage: String?
    @State private var sending = false
    @FocusState private var focusedField: CardField?

    var onDone: (_ created: Bool, _ cardName: String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Card title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focusedField, equals: .title)
                .onSubmit { submit() }
                .onKeyPress { focusMove($0, forward: .description, backward: .taskList) }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                fieldEditor(text: $descriptionText, field: .description,
                            next: .taskList, previous: .title, minHeight: 48)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Task List").font(.caption).foregroundStyle(.secondary)
                fieldEditor(text: $taskListText, field: .taskList,
                            next: .title, previous: .description, minHeight: 72)
                Text("First line is the list title, then one task per “- ” line.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

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
                Text("⇥ next field · ↩ add · ⌘↩ add from a box · ⎋ cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if sending { ProgressView().controlSize(.small) }
                Button("Cancel") { onDone(false, nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add Card") { submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear {
            focusedField = .title
            // Background refresh so the dropdowns are current; cache renders instantly.
            Task {
                await data.refreshProjects()
                if !boardId.isEmpty { await data.refreshBoard(boardId) }
                validateSelections()
            }
        }
        .onChange(of: projectId) { _, newValue in
            boardId = data.boards(forProject: newValue).first?.id ?? ""
        }
        .onChange(of: boardId) { _, newValue in
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

    /// A bordered multiline box wired into the Tab loop. Tab / Shift-Tab move
    /// focus; ⌘Return saves; a bare Return stays a newline (task-per-line).
    private func fieldEditor(text: Binding<String>, field: CardField,
                             next: CardField, previous: CardField,
                             minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: minHeight)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .focused($focusedField, equals: field)
            .onKeyPress { focusMove($0, forward: next, backward: previous) }
            .onKeyPress(keys: [.return]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                submit()
                return .handled
            }
    }

    /// Tab / Shift-Tab focus move. Robust to how the tab key arrives: Shift-Tab
    /// can be delivered as a "backtab" character (U+0019) rather than a plain
    /// tab, which `onKeyPress(keys: [.tab])` misses.
    private func focusMove(_ press: KeyPress, forward: CardField, backward: CardField) -> KeyPress.Result {
        let isTab = press.key == .tab || press.characters == "\t" || press.characters == "\u{19}"
        guard isTab else { return .ignored }
        focusedField = press.modifiers.contains(.shift) ? backward : forward
        return .handled
    }

    /// Parses the task-list box. First non-empty non-bullet line is the title;
    /// lines beginning with "-", "*", or "•" are tasks. Returns nil when empty.
    private func parseTaskList() -> PlankaClient.TaskListInput? {
        let lines = taskListText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var title = "Tasks"
        var titleSet = false
        var tasks: [String] = []
        let bullets: Set<Character> = ["-", "*", "•"]
        for line in lines {
            if let first = line.first, bullets.contains(first) {
                let task = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !task.isEmpty { tasks.append(task) }
            } else if !titleSet {
                title = line
                titleSet = true
            } else {
                // Non-bullet line after the title: treat it as a task too.
                tasks.append(line)
            }
        }
        return PlankaClient.TaskListInput(title: title, tasks: tasks)
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
        let description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskList = parseTaskList()
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
                    listId: list, name: name, position: position, labelId: label,
                    description: description.isEmpty ? nil : description,
                    taskList: taskList)
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
