import AppKit
import SwiftUI

extension MainWindowView {
    var accountsSettings: some View {
        AccountsSettingsPage(
            providerStore: providerStore,
            accountsUseKeychain: $accountsUseKeychain,
            accountsLockWithPassword: $accountsLockWithPassword,
            accountsLockTimeout: $accountsLockTimeout,
            accountsSyncPreferences: $accountsSyncPreferences,
            accountsSyncMemories: $accountsSyncMemories
        )
    }
}

private struct AccountsSettingsPage: View {
    @ObservedObject var providerStore: ProviderAccountStore
    @Binding var accountsUseKeychain: Bool
    @Binding var accountsLockWithPassword: Bool
    @Binding var accountsLockTimeout: String
    @Binding var accountsSyncPreferences: Bool
    @Binding var accountsSyncMemories: Bool
    @State private var presentedProvider: IntelligenceProviderID?
    @State private var securityController = AppSecurityController()

    var body: some View {
        Form {
            Section {
                ForEach(IntelligenceProviderID.connectableProviders) { providerID in
                    providerConnectionRow(for: providerID)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("OpenAI is live in this build. Other providers still use local placeholder flows while the backend architecture expands.")
            }

            Section {
                explainedToggle(
                    "Store secrets in Keychain",
                    description: "Stores provider keys in Keychain when available.",
                    isOn: $accountsUseKeychain
                )
                explainedToggle(
                    "Protect account changes with password / Touch ID",
                    description: "Requires authentication before you view a saved key or change an account.",
                    isOn: protectedAccountChangesBinding
                )
                .disabled(securityController.isAuthenticating)
                if accountsLockWithPassword {
                    explainedPicker(
                        "Ask again after",
                        description: "How long account management stays unlocked before HUSH asks again.",
                        selection: protectedAccountTimeoutBinding
                    ) {
                        Text("Immediately").tag("immediate")
                        Text("1 minute").tag("1min")
                        Text("5 minutes").tag("5min")
                        Text("30 minutes").tag("30min")
                    }
                    .disabled(securityController.isAuthenticating)
                }
            } header: {
                Text("Security")
            } footer: {
                Text("Security covers local storage and sensitive account actions on this Mac.")
            }

            Section {
                explainedToggle(
                    "Sync preferences across devices",
                    description: "Keeps settings in sync across your devices.",
                    isOn: $accountsSyncPreferences
                )
                explainedToggle(
                    "Sync memories & prompts",
                    description: "Keeps saved memories and prompt presets in sync.",
                    isOn: $accountsSyncMemories
                )
            } header: {
                Text("Sync")
            } footer: {
                Text("Sync stays local to HUSH in this build.")
            }
        }
        .settingsPageLayout()
        .sheet(item: $presentedProvider) { providerID in
            ProviderAccountsManagementSheet(
                providerStore: providerStore,
                providerID: providerID,
                securityController: securityController
            )
        }
        .accountAuthorizationAlert(using: securityController)
        .onAppear {
            IntelligencePreferencesMigration.migrateIfNeeded()
            securityController.refreshConfiguration()
        }
        .onChange(of: accountsLockWithPassword) { _, isEnabled in
            if isEnabled {
                securityController.refreshConfiguration()
            } else {
                securityController.clearApproval()
            }
        }
        .onChange(of: accountsLockTimeout) { _, _ in
            securityController.refreshConfiguration()
        }
    }

    @ViewBuilder
    private func providerConnectionRow(for providerID: IntelligenceProviderID) -> some View {
        let accounts = providerStore.accounts(for: providerID)
        let hasConnections = accounts.isEmpty == false

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Label(providerID.title, systemImage: providerID.icon)
                    .font(.body.weight(.medium))

                Spacer(minLength: 12)

                Text(hasConnections ? "\(accounts.count) connected" : "Not connected")
                    .font(.caption)
                    .foregroundStyle(hasConnections ? .secondary : .tertiary)

                Button(hasConnections ? "Manage…" : "Connect…") {
                    runAuthorizedAccountAction(
                        using: securityController,
                        reason: hasConnections
                            ? "Manage \(providerID.title) accounts"
                            : "Connect a \(providerID.title) account",
                        beginSession: true
                    ) {
                        presentedProvider = providerID
                    }
                }
                .disabled(securityController.isAuthenticating)
            }

            Text(providerID.helperText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let account = accounts.first {
                Text(account.displayName + " · " + account.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if providerID == .openAI {
                    let status = providerStore.statusSummary(for: account)
                    Text(status.title + " · " + status.detail)
                        .font(.caption)
                        .foregroundStyle(status.isError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let usage = status.usage {
                        AccountStatusMetricGrid(usage: usage)
                            .padding(.top, 2)
                    }
                }
            }

            if accounts.count > 1 {
                Text("+ \(accounts.count - 1) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var protectedAccountChangesBinding: Binding<Bool> {
        Binding(
            get: { accountsLockWithPassword },
            set: { newValue in
                guard newValue != accountsLockWithPassword else { return }

                if newValue {
                    accountsLockWithPassword = true
                    securityController.refreshConfiguration()
                    return
                }

                runAuthorizedAccountAction(
                    using: securityController,
                    reason: "Turn off account protection",
                    requireFreshApproval: true
                ) {
                    accountsLockWithPassword = false
                    securityController.clearApproval()
                }
            }
        )
    }

    private var protectedAccountTimeoutBinding: Binding<String> {
        Binding(
            get: { accountsLockTimeout },
            set: { newValue in
                guard newValue != accountsLockTimeout else { return }

                runAuthorizedAccountAction(
                    using: securityController,
                    reason: "Change when HUSH asks again for account changes",
                    requireFreshApproval: true
                ) {
                    accountsLockTimeout = newValue
                    securityController.refreshConfiguration()
                }
            }
        )
    }

}

private extension AccountsSettingsPage {
    func explainedToggle(_ title: String, description: String, isOn: Binding<Bool>) -> some View {
        settingsToggle(title, description: description, isOn: isOn)
    }

    func explainedPicker<SelectionValue: Hashable, Content: View>(
        _ title: String,
        description: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsPicker(title, description: description, selection: selection, content: content)
    }
}

private struct ProviderAccountsManagementSheet: View {
    @ObservedObject var providerStore: ProviderAccountStore
    let providerID: IntelligenceProviderID
    let securityController: AppSecurityController
    @Environment(\.dismiss) private var dismiss
    @State private var editorDraft: ProviderAccountEditorDraft?

    private var providerAccounts: [ProviderAccountRecord] {
        providerStore.accounts(for: providerID)
    }

    private var primaryAccount: ProviderAccountRecord? {
        providerAccounts.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(providerID.title, systemImage: providerID.icon)
                            .font(.title3.weight(.semibold))
                        Text(providerID.helperText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Connection")
                }

                if providerID == .openAI {
                    Section {
                        Button("Sign In to OpenAI…") {
                            openExternalURL(OpenAIConsoleDestination.login.urlString)
                        }
                        Button("Open API Keys") {
                            openExternalURL(OpenAIConsoleDestination.apiKeys.urlString)
                        }
                        Button("Open Usage") {
                            openExternalURL(OpenAIConsoleDestination.usage.urlString)
                        }
                        Button("Open Billing") {
                            openExternalURL(OpenAIConsoleDestination.billing.urlString)
                        }
                    } header: {
                        Text("OpenAI Console")
                    } footer: {
                        Text("OpenAI account sign-in and exact billing balance live in the OpenAI dashboard. HUSH uses local API keys on this Mac.")
                    }

                }

                Section {
                    if providerAccounts.isEmpty {
                        ContentUnavailableView(
                            "No Accounts",
                            systemImage: providerID.icon,
                            description: Text(emptyStateDescription)
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(providerAccounts) { account in
                            accountRow(account)
                        }
                    }
                } header: {
                    Text("Saved Accounts")
                }

                Section {
                    if providerID == .openAI {
                        Button("Add OpenAI Keys…") {
                            runAuthorizedAccountAction(
                                using: securityController,
                                reason: "Add OpenAI API keys"
                            ) {
                                editorDraft = ProviderAccountEditorDraft(
                                    providerID: providerID,
                                    authMethod: .apiKey
                                )
                            }
                        }
                        .disabled(securityController.isAuthenticating)
                    } else {
                        if providerID.supportsOAuth {
                            Button("Sign In to \(providerID.title)") {
                                runAuthorizedAccountAction(
                                    using: securityController,
                                    reason: "Add a \(providerID.title) sign-in"
                                ) {
                                    editorDraft = ProviderAccountEditorDraft(
                                        providerID: providerID,
                                        authMethod: .oauth
                                    )
                                }
                            }
                            .disabled(securityController.isAuthenticating)
                        }

                        if providerID.supportsAPIKeys {
                            Button("Add API Key") {
                                runAuthorizedAccountAction(
                                    using: securityController,
                                    reason: "Add a \(providerID.title) API key"
                                ) {
                                    editorDraft = ProviderAccountEditorDraft(
                                        providerID: providerID,
                                        authMethod: .apiKey
                                    )
                                }
                            }
                            .disabled(securityController.isAuthenticating)
                        }
                    }
                } header: {
                    Text("Add Connection")
                } footer: {
                    Text(addConnectionFooter)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(providerID.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 500)
        .sheet(item: $editorDraft) { draft in
            ProviderAccountEditorSheet(
                providerStore: providerStore,
                securityController: securityController,
                draft: draft
            )
        }
        .accountAuthorizationAlert(using: securityController)
        .onDisappear {
            securityController.endAuthorizationSession()
        }
    }

    private var emptyStateDescription: String {
        if providerID == .openAI {
            return "Sign in on the OpenAI dashboard, create a project API key, and paste it here. Add an admin key if you want usage and cost status."
        }

        return "Add a local sign-in or API key for \(providerID.title)."
    }

    private var addConnectionFooter: String {
        if providerID == .openAI {
            return "Project API keys power Responses API calls. Admin keys are optional, but required for the organization usage and costs endpoints."
        }

        return "Changes here update HUSH locally for testing."
    }

    @ViewBuilder
    private func accountRow(_ account: ProviderAccountRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.displayName)
                        .font(.body.weight(.medium))

                    Text(account.methodTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(account.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if providerID == .openAI {
                    let status = providerStore.statusSummary(for: account)
                    Text(status.title + " · " + status.detail)
                        .font(.caption)
                        .foregroundStyle(status.isError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Updated \(account.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Button("Edit") {
                runAuthorizedAccountAction(
                    using: securityController,
                    reason: "Edit \(account.displayName)"
                ) {
                    editorDraft = ProviderAccountEditorDraft(
                        account: account,
                        secrets: providerStore.secrets(for: account)
                    )
                }
            }
            .disabled(securityController.isAuthenticating)

            Button("Delete", role: .destructive) {
                runAuthorizedAccountAction(
                    using: securityController,
                    reason: "Delete \(account.displayName)"
                ) {
                    providerStore.deleteAccount(account)
                }
            }
            .disabled(securityController.isAuthenticating)
        }
        .padding(.vertical, 2)
    }
}

private struct ProviderAccountEditorDraft: Identifiable {
    let id: UUID
    let existingAccountID: UUID?
    let createdAt: Date
    let providerID: IntelligenceProviderID
    var authMethod: ProviderAccountAuthMethod
    var displayName: String
    var identifier: String
    var apiKey: String
    var adminKey: String
    var organizationID: String
    var projectID: String

    init(
        providerID: IntelligenceProviderID,
        authMethod: ProviderAccountAuthMethod
    ) {
        id = UUID()
        existingAccountID = nil
        createdAt = Date()
        self.providerID = providerID
        self.authMethod = authMethod
        displayName = providerID == .openAI ? "OpenAI" : ""
        identifier = ""
        apiKey = ""
        adminKey = ""
        organizationID = ""
        projectID = ""
    }

    init(account: ProviderAccountRecord, secrets: ProviderAccountLocalSecrets) {
        id = account.id
        existingAccountID = account.id
        createdAt = account.createdAt
        providerID = account.providerID
        authMethod = account.authMethod
        displayName = account.displayName
        identifier = account.identifier
        apiKey = secrets.apiKey
        adminKey = secrets.adminKey
        organizationID = account.organizationID
        projectID = account.projectID
    }

    var isNew: Bool {
        existingAccountID == nil
    }

    var isOpenAI: Bool {
        providerID == .openAI
    }

    var title: String {
        if isNew {
            if isOpenAI {
                return "Connect OpenAI"
            }
            return authMethod == .oauth ? "Sign In" : "Add API Key"
        }

        return "Edit Account"
    }

    var saveTitle: String {
        if isOpenAI {
            return isNew ? "Connect" : "Update"
        }
        return isNew ? "Save" : "Update"
    }

    var detailText: String {
        if isOpenAI {
            return "Use an OpenAI project API key for model requests. Add an admin key if you want usage and cost status."
        }
        return authMethod.detailText
    }

    var displayNameTitle: String {
        if isOpenAI {
            return "Connection Name"
        }
        return authMethod == .oauth ? "Account Name" : "Key Name"
    }

    var identifierTitle: String {
        if isOpenAI {
            return "Key Label"
        }
        return authMethod == .oauth ? "Email or Username" : "Key Label"
    }

    var apiKeyTitle: String {
        isOpenAI ? "Project API Key" : "API Key"
    }

    var adminKeyTitle: String {
        "Admin API Key (Optional)"
    }

    var isSaveEnabled: Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedIdentifier.isEmpty else {
            return false
        }

        if authMethod.requiresSecretEntry {
            return !trimmedAPIKey.isEmpty
        }

        return true
    }

    func makeUpsert(preferKeychain: Bool) -> ProviderAccountUpsert {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedAPIKey: String

        if authMethod.requiresSecretEntry {
            storedAPIKey = trimmedAPIKey
        } else if !trimmedAPIKey.isEmpty {
            storedAPIKey = trimmedAPIKey
        } else {
            storedAPIKey = "local-auth-\(UUID().uuidString.prefix(12))"
        }

        let trimmedAdminKey = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let localSecrets = ProviderAccountLocalSecrets(
            apiKey: storedAPIKey,
            adminKey: trimmedAdminKey
        )

        let record = ProviderAccountRecord(
            id: existingAccountID ?? id,
            providerID: providerID,
            authMethod: authMethod,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines),
            organizationID: organizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            projectID: projectID.trimmingCharacters(in: .whitespacesAndNewlines),
            usesKeychain: preferKeychain,
            localSecrets: preferKeychain ? .empty : localSecrets,
            createdAt: createdAt,
            updatedAt: Date()
        )

        return ProviderAccountUpsert(record: record, secrets: localSecrets)
    }
}

private struct ProviderAccountEditorSheet: View {
    @ObservedObject var providerStore: ProviderAccountStore
    let securityController: AppSecurityController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("accounts.useKeychain") private var accountsUseKeychain = true
    @State private var draft: ProviderAccountEditorDraft
    @State private var isSecretVisible = false
    @State private var isAdminSecretVisible = false

    init(
        providerStore: ProviderAccountStore,
        securityController: AppSecurityController,
        draft: ProviderAccountEditorDraft
    ) {
        self.providerStore = providerStore
        self.securityController = securityController
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(draft.providerID.title, systemImage: draft.providerID.icon)
                            .font(.headline)
                        Text(draft.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Method")
                }

                Section {
                    TextField(draft.displayNameTitle, text: $draft.displayName)
                    TextField(draft.identifierTitle, text: $draft.identifier)

                    if draft.isOpenAI {
                        TextField("Organization ID (Optional)", text: $draft.organizationID)
                        TextField("Project ID (Optional)", text: $draft.projectID)
                    }

                    if draft.authMethod.requiresSecretEntry {
                        secureEntryRow(
                            title: draft.apiKeyTitle,
                            text: $draft.apiKey,
                            isVisible: $isSecretVisible,
                            revealReason: "Reveal the stored \(draft.providerID.title) API key"
                        )
                    }

                    if draft.isOpenAI {
                        secureEntryRow(
                            title: draft.adminKeyTitle,
                            text: $draft.adminKey,
                            isVisible: $isAdminSecretVisible,
                            revealReason: "Reveal the stored OpenAI admin key"
                        )
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text(detailsFooterText)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.saveTitle) {
                        runAuthorizedAccountAction(
                            using: securityController,
                            reason: draft.isNew
                                ? "Save a new \(draft.providerID.title) account"
                                : "Update \(draft.displayName)"
                        ) {
                            providerStore.saveAccount(draft.makeUpsert(preferKeychain: accountsUseKeychain))
                            dismiss()
                        }
                    }
                    .disabled(!draft.isSaveEnabled)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .accountAuthorizationAlert(using: securityController)
    }

    private var detailsFooterText: String {
        if draft.isOpenAI {
            return "Project API keys power Responses API calls. Admin keys are required for the organization costs and completions usage endpoints."
        }

        return "Saving updates the local account in HUSH."
    }

    @ViewBuilder
    private func secureEntryRow(
        title: String,
        text: Binding<String>,
        isVisible: Binding<Bool>,
        revealReason: String
    ) -> some View {
        HStack(spacing: 8) {
            Group {
                if isVisible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }

            Button {
                if isVisible.wrappedValue {
                    isVisible.wrappedValue = false
                } else {
                    runAuthorizedAccountAction(
                        using: securityController,
                        reason: revealReason,
                        requireFreshApproval: true
                    ) {
                        isVisible.wrappedValue = true
                    }
                }
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .disabled(securityController.isAuthenticating)
        }
    }
}

private enum OpenAIConsoleDestination {
    case login
    case apiKeys
    case usage
    case billing

    var urlString: String {
        switch self {
        case .login:
            return "https://platform.openai.com/login"
        case .apiKeys:
            return "https://platform.openai.com/settings/organization/api-keys"
        case .usage:
            return "https://platform.openai.com/settings/organization/usage"
        case .billing:
            return "https://platform.openai.com/settings/organization/billing/overview"
        }
    }
}

private func openExternalURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
}

private struct AccountAuthorizationAlertModifier: ViewModifier {
    let securityController: AppSecurityController

    func body(content: Content) -> some View {
        content.alert(
            "Authentication Required",
            isPresented: Binding(
                get: { securityController.authorizationErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        securityController.clearAuthorizationError()
                    }
                }
            )
        ) {
            Button("OK") {
                securityController.clearAuthorizationError()
            }
        } message: {
            Text(securityController.authorizationErrorMessage ?? "")
        }
    }
}

private struct AccountStatusMetricGrid: View {
    let usage: ProviderAccountUsageSnapshot

    private let columns = [
        GridItem(.flexible(minimum: 110), spacing: 10),
        GridItem(.flexible(minimum: 110), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                metricTile(title: "Models", value: formattedMetricCount(usage.modelCount))
                metricTile(
                    title: "7d Spend",
                    value: usage.spendText ?? (usage.hasAdminKey ? "$0.00" : "Add admin key")
                )
                metricTile(
                    title: "Requests",
                    value: usage.requestCount.map(formattedMetricCount) ?? (usage.hasAdminKey ? "0" : "Add admin key")
                )
                metricTile(
                    title: "Tokens",
                    value: usage.totalTokens.map(formattedMetricCount) ?? (usage.hasAdminKey ? "0" : "Add admin key")
                )
            }

            HStack(spacing: 8) {
                if let organizationSummary = usage.organizationSummary {
                    statusChip("Org \(organizationSummary)")
                }

                if let projectSummary = usage.projectSummary {
                    statusChip("Project \(projectSummary)")
                }

                statusChip(usage.hasAdminKey ? "Admin key added" : "Admin key missing")
            }
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

private func formattedMetricCount(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

private extension View {
    func accountAuthorizationAlert(using securityController: AppSecurityController) -> some View {
        modifier(AccountAuthorizationAlertModifier(securityController: securityController))
    }
}

@MainActor
private func runAuthorizedAccountAction(
    using securityController: AppSecurityController,
    reason: String,
    requireFreshApproval: Bool = false,
    beginSession: Bool = false,
    action: @escaping @MainActor () -> Void
) {
    Task { @MainActor in
        if await securityController.authorizeAccountAccessIfNeeded(
            reason: reason,
            requireFreshApproval: requireFreshApproval
        ) {
            if beginSession {
                securityController.beginAuthorizationSession()
            }
            action()
        }
    }
}
