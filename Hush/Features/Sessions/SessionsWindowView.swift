import SwiftUI

private enum SessionListFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .pinned:
            return "Pinned"
        case .archived:
            return "Archive"
        }
    }
}

private struct SessionRenameDraft: Identifiable {
    let id: UUID
    let sessionID: UUID
    let isCurrentSession: Bool
    let automaticTitle: String
    let existingTitle: String

    init(session: SessionRecord, isCurrentSession: Bool) {
        id = session.id
        sessionID = session.id
        self.isCurrentSession = isCurrentSession
        automaticTitle = SessionRenameDraft.automaticTitle(for: session)
        existingTitle = session.customTitle ?? ""
    }

    private static func automaticTitle(for session: SessionRecord) -> String {
        let existingTitle = session.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !existingTitle.isEmpty {
            return existingTitle
        }

        let derivedTitle = session.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return derivedTitle.isEmpty ? "Assistant" : derivedTitle
    }
}

struct SessionsWindowView: View {
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var workspace: AssistantWorkspace
    @State private var store = SessionHistoryStore.shared
    @AppStorage("sessions.browser.filter") private var selectedFilterRaw = SessionListFilter.all.rawValue
    @State private var searchText = ""
    @State private var renameDraft: SessionRenameDraft?

    private var selectedFilter: SessionListFilter {
        get { SessionListFilter(rawValue: selectedFilterRaw) ?? .all }
        nonmutating set { selectedFilterRaw = newValue.rawValue }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowCurrentSession: Bool {
        switch selectedFilter {
        case .all:
            return true
        case .pinned:
            return store.currentSession.isPinned
        case .archived:
            return false
        }
    }

    private var filteredSavedSessions: [SessionRecord] {
        switch selectedFilter {
        case .all:
            return store.activeSessions
        case .pinned:
            return store.pinnedSessions
        case .archived:
            return store.archivedSessions
        }
    }

    private var filteredSearchResults: [SessionSearchResult] {
        store.sessionSearchResults(for: searchText)
            .filter { result in
                matchesSelectedFilter(result.session, isCurrent: result.session.id == store.currentSession.id)
            }
    }

    var body: some View {
        List {
            if isSearching {
                searchResultsSection
            } else {
                if shouldShowCurrentSession {
                    Section("Current") {
                        sessionRow(session: store.currentSession, isCurrent: true)
                    }
                }

                Section(savedSessionsSectionTitle) {
                    if filteredSavedSessions.isEmpty {
                        emptyStateRow(emptyStateText)
                    } else {
                        ForEach(filteredSavedSessions) { session in
                            sessionRow(session: session, isCurrent: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $searchText, prompt: "Search sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(selection: filterBinding) {
                    ForEach(SessionListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                } label: {
                    Label(selectedFilter.title, systemImage: "line.3.horizontal.decrease.circle")
                }
                .pickerStyle(.menu)
            }
        }
        .sheet(item: $renameDraft) { draft in
            SessionRenameSheet(draft: draft) { updatedTitle in
                performOnMainActor {
                    store.renameSession(id: draft.sessionID, title: updatedTitle)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section(filteredSearchResults.isEmpty ? "Results" : "Matches") {
            if filteredSearchResults.isEmpty {
                emptyStateRow("No matching sessions", detail: "Try a shorter phrase or switch the current filter.")
            } else {
                ForEach(filteredSearchResults) { result in
                    sessionRow(
                        session: result.session,
                        isCurrent: result.session.id == store.currentSession.id,
                        detailOverride: result.snippet
                    )
                }
            }
        }
    }

    private var savedSessionsSectionTitle: String {
        switch selectedFilter {
        case .all:
            return "Saved"
        case .pinned:
            return "Pinned"
        case .archived:
            return "Archived"
        }
    }

    private var emptyStateText: String {
        switch selectedFilter {
        case .all:
            return "No saved sessions yet."
        case .pinned:
            return "Pinned sessions show up here."
        case .archived:
            return "Archived sessions show up here."
        }
    }

    private var filterBinding: Binding<SessionListFilter> {
        Binding(
            get: { selectedFilter },
            set: { selectedFilter = $0 }
        )
    }

    private func matchesSelectedFilter(_ session: SessionRecord, isCurrent: Bool) -> Bool {
        switch selectedFilter {
        case .all:
            return isCurrent || !session.isArchived
        case .pinned:
            return session.isPinned && !session.isArchived
        case .archived:
            return !isCurrent && session.isArchived
        }
    }

    private func sessionRow(
        session: SessionRecord,
        isCurrent: Bool,
        detailOverride: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                openSession(session, isCurrent: isCurrent)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    sessionGlyph(session: session, isCurrent: isCurrent)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(session.displayTitle)
                                .font(.body.weight(.medium))
                                .lineLimit(1)

                            if isCurrent {
                                statusBadge(title: "Current", systemImage: "circle.fill")
                            }

                            if session.isPinned {
                                statusBadge(title: "Pinned", systemImage: "pin.fill")
                            }

                            if session.isArchived {
                                statusBadge(title: "Archived", systemImage: "archivebox.fill")
                            }
                        }

                        Text(sessionSubtitle(for: session))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(detailOverride ?? sessionDetail(for: session, isCurrent: isCurrent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                sessionActionItems(session: session, isCurrent: isCurrent)
            }

            Menu {
                sessionActionItems(session: session, isCurrent: isCurrent)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func sessionActionItems(session: SessionRecord, isCurrent: Bool) -> some View {
        Button("Open") {
            openSession(session, isCurrent: isCurrent)
        }

        Button(session.isPinned ? "Unpin" : "Pin") {
            performOnMainActor {
                store.togglePinned(for: session.id)
            }
        }

        Button("Rename…") {
            renameDraft = SessionRenameDraft(session: session, isCurrentSession: isCurrent)
        }

        ShareLink(
            item: sessionShareText(for: session),
            preview: SharePreview(session.displayTitle)
        ) {
            Label("Share…", systemImage: "square.and.arrow.up")
        }

        Button(session.isArchived ? "Unarchive" : archiveActionTitle(isCurrent: isCurrent)) {
            performOnMainActor {
                store.setArchived(!session.isArchived, for: session.id)
            }
        }
        .disabled(isCurrent && !session.hasContent)

        Divider()

        Button(isCurrent ? "Delete Current Session" : "Delete Session", role: .destructive) {
            performOnMainActor {
                store.deleteSession(id: session.id)
            }
        }
    }

    private func archiveActionTitle(isCurrent: Bool) -> String {
        isCurrent ? "Archive and Start New Session" : "Archive"
    }

    private func openSession(_ session: SessionRecord, isCurrent: Bool) {
        performOnMainActor {
            workspace.openSession(session, isCurrentSession: isCurrent)
            appModel.showMainWindow(.assistant)
        }
    }

    private func sessionSubtitle(for session: SessionRecord) -> String {
        let messageCount = max(0, session.interactionCount)
        return "\(dateTime(session.lastActivityAt)) • \(messageCount) message\(messageCount == 1 ? "" : "s")"
    }

    private func sessionDetail(for session: SessionRecord, isCurrent: Bool) -> String {
        if let lastResponse = session.interactions.last?.response.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastResponse.isEmpty {
            return sessionPreview(lastResponse)
        }

        if let lastPrompt = session.interactions.last?.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastPrompt.isEmpty {
            return sessionPreview(lastPrompt)
        }

        if let lastError = session.errors.last {
            return sessionPreview(lastError.title + ": " + lastError.message)
        }

        if isCurrent {
            return "Start a new conversation, then pin or archive it once it becomes something worth keeping."
        }

        return "No saved messages yet."
    }

    private func sessionShareText(for session: SessionRecord) -> String {
        var lines = [session.displayTitle]
        lines.append("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        if session.interactions.isEmpty {
            lines.append("No saved messages yet.")
        } else {
            for interaction in session.interactions {
                if !interaction.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("You")
                    lines.append(interaction.prompt)
                    lines.append("")
                }

                if !interaction.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("HUSH")
                    lines.append(interaction.response)
                    lines.append("")
                }
            }
        }

        if !session.errors.isEmpty {
            lines.append("Errors")
            for error in session.errors {
                lines.append("\(error.title): \(error.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func statusBadge(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }

    private func sessionGlyph(session: SessionRecord, isCurrent: Bool) -> some View {
        let symbolName: String

        if isCurrent {
            symbolName = "circle.fill"
        } else if session.isArchived {
            symbolName = "archivebox.fill"
        } else if session.isPinned {
            symbolName = "pin.fill"
        } else {
            symbolName = "message.fill"
        }

        return Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(isCurrent ? 0.9 : 0.72))
            .frame(width: 20, height: 20, alignment: .center)
    }

    private func emptyStateRow(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionPreview(_ value: String, limit: Int = 160) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > limit else { return normalized }
        let cutoffIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return String(normalized[..<cutoffIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func performOnMainActor(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            action()
        }
    }
}

private struct SessionRenameSheet: View {
    let draft: SessionRenameDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(draft: SessionRenameDraft, onSave: @escaping (String) -> Void) {
        self.draft = draft
        self.onSave = onSave
        _title = State(initialValue: draft.existingTitle)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Use a custom title, or leave it empty to fall back to the automatic title.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField(draft.automaticTitle, text: $title)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatic title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(draft.automaticTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(draft.isCurrentSession ? "Rename Current Session" : "Rename Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}

#Preview {
    SessionsWindowView()
        .environment(AppModel.shared)
        .environmentObject(AssistantWorkspace.shared)
}
