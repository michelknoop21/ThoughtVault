// AdminView.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Admin panel with 5 tabs: Overzicht, Gebruikers, Uitnodigingen, Bug Rapporten, Fouten.
// Visible only when the authenticated user's role is "admin".

import SwiftUI

// MARK: - Admin Tab

enum AdminTab: String, CaseIterable {
    case overzicht = "Overzicht"
    case gebruikers = "Gebruikers"
    case uitnodigingen = "Uitnodigingen"
    case feedback = "Feedback"
    case fouten = "Fouten"
    case instellingen = "Instellingen"

    var icon: String {
        switch self {
        case .overzicht: return "chart.bar.fill"
        case .gebruikers: return "person.2.fill"
        case .uitnodigingen: return "envelope.fill"
        case .feedback: return "bubble.left.and.text.bubble.right.fill"
        case .fouten: return "exclamationmark.triangle.fill"
        case .instellingen: return "gearshape.fill"
        }
    }
}

enum LogSubTab: String, CaseIterable {
    case activity = "Activiteit"
    case errors = "Fouten"
}

private let logPageSize = 25

// MARK: - AdminView

struct AdminView: View {

    @Environment(AuthViewModel.self) var authVM
    @State private var selectedTab: AdminTab = .overzicht
    @State private var users: [AdminUser] = []
    @State private var stats: AdminStats? = nil
    @State private var invitations: [AdminInvitation] = []
    @State private var feedbackItems: [AdminFeedback] = []
    @State private var errors: [AdminError] = []
    @State private var activityLogs: [AdminActivity] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

    // Logging tab state
    @State private var logSubTab: LogSubTab = .activity
    @State private var logSearch = ""
    @State private var logSeverityFilter = ""
    @State private var logUserFilter = ""
    @State private var logTypeFilter = ""
    @State private var logPage = 1
    @State private var isLoadingLogs = false
    @State private var expandedLogRow: Int? = nil
    @State private var showCreateUserSheet = false
    @State private var showCreateInvitationSheet = false
    @State private var userToDelete: AdminUser? = nil
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

    // Create user form
    @State private var newUserEmail = ""
    @State private var newUserPassword = ""
    @State private var newUserName = ""
    @State private var newUserRole = "user"

    // Feedback filter
    @State private var showArchivedFeedback = false
    @State private var feedbackToDelete: AdminFeedback? = nil
    @State private var showDeleteFeedbackConfirm = false

    // Create invitation form
    @State private var newInviteMaxUses = 1
    @State private var newInviteExpiresHours = 48

    // Admin settings
    @State private var ms365ClientId = ""
    @State private var ms365TenantId = ""
    @State private var googleOAuthClientIdMacos = ""
    @State private var googleOAuthClientIdWindows = ""
    @State private var youtubeMaxDurationMinutes = "120"
    @State private var youtubeCookiesContent = ""
    @State private var youtubeExtractorArgs = "youtube:player_client=web;fetch_pot=always"
    @State private var youtubeProxy = ""
    @State private var isLoadingSettings = false
    @State private var showSettingsSaved = false

    var filteredUsers: [AdminUser] {
        if searchText.isEmpty { return users }
        return users.filter {
            $0.email.localizedCaseInsensitiveContains(searchText)
            || ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if authVM.currentUser?.role?.lowercased() != "admin" {
                accessDeniedView
            } else {
                adminContent
            }
        }
        .navigationTitle("Admin Panel")
        .task {
            await loadData()
        }
        .alert(
            "Gebruiker verwijderen?",
            isPresented: $showDeleteConfirm,
            presenting: userToDelete
        ) { user in
            Button("Verwijderen", role: .destructive) {
                Task { await deleteUser(user) }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { user in
            Text("Weet je zeker dat je \(user.email) wilt verwijderen? Dit kan niet ongedaan worden gemaakt.")
        }
        .sheet(isPresented: $showCreateUserSheet) {
            createUserSheet
        }
        .sheet(isPresented: $showCreateInvitationSheet) {
            createInvitationSheet
        }
        .alert(
            "Feedback verwijderen?",
            isPresented: $showDeleteFeedbackConfirm,
            presenting: feedbackToDelete
        ) { item in
            Button("Verwijderen", role: .destructive) {
                Task { await deleteFeedback(item) }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { _ in
            Text("Dit kan niet ongedaan worden gemaakt.")
        }
    }

    // MARK: - Access Denied

    private var accessDeniedView: some View {
        VStack(spacing: TS.Spacing.lg) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.statusError.opacity(0.6))

            Text("Geen toegang")
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)

            Text("Het admin-paneel is alleen toegankelijk voor beheerders.")
                .font(TS.Font.callout)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Admin Content

    private var adminContent: some View {
        VStack(spacing: 0) {
            tabBar
            tabContent
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        // Native segmented control: keyboard-traversable + VoiceOver tab semantics,
        // replacing a hand-rolled matchedGeometryEffect bar.
        Picker("Sectie", selection: $selectedTab) {
            ForEach(AdminTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
        .background(Color.surfaceSecondary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if isLoading {
            Spacer()
            ProgressView("Gegevens laden...")
                .foregroundStyle(Color.labelSecondary)
            Spacer()
        } else if let error = errorMessage {
            Spacer()
            VStack(spacing: TS.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.statusError)
                Text(error)
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                Button("Opnieuw proberen") {
                    Task { await loadData() }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding()
            Spacer()
        } else {
            switch selectedTab {
            case .overzicht:
                overzichtTab
            case .gebruikers:
                gebruikersTab
            case .uitnodigingen:
                uitnodigingenTab
            case .feedback:
                feedbackTab
            case .fouten:
                foutenTab
            case .instellingen:
                instellingenTab
            }
        }
    }

    // MARK: - Overzicht Tab

    private var overzichtTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.md) {
                Text("Systeem statistieken")
                    .font(TS.Font.captionSemibold)
                    .foregroundStyle(Color.labelSecondary)
                    .padding(.horizontal, TS.Spacing.xs)

                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: TS.Spacing.md
                ) {
                    statCard(
                        value: "\(stats?.totalUsers ?? 0)",
                        label: "Gebruikers",
                        icon: "person.2.fill",
                        color: Color.brandPrimary
                    )
                    statCard(
                        value: "\(stats?.totalNotes ?? 0)",
                        label: "Notulen",
                        icon: "doc.text.fill",
                        color: Color.statusSuccess
                    )
                    statCard(
                        value: "\(stats?.transcriptionsToday ?? 0)",
                        label: "Transcripties vandaag",
                        icon: "waveform",
                        color: Color.brandOrange
                    )
                    statCard(
                        value: "\(stats?.errors7d ?? 0)",
                        label: "Fouten (7 dagen)",
                        icon: "exclamationmark.triangle.fill",
                        color: Color.statusError
                    )
                }
            }
            .padding(TS.Spacing.md)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)

            Text(value)
                .font(TS.Font.titleBold)
                .foregroundStyle(Color.labelPrimary)

            Text(label)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TS.Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .fill(Color.surfaceSecondary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous)
                .stroke(Color.borderSecondary, lineWidth: 1)
        }
    }

    // MARK: - Gebruikers Tab

    private var gebruikersTab: some View {
        VStack(spacing: 0) {
            // Header with create button
            HStack {
                Spacer()
                Button {
                    newUserEmail = ""
                    newUserPassword = ""
                    newUserName = ""
                    newUserRole = "user"
                    showCreateUserSheet = true
                } label: {
                    Label("Gebruiker aanmaken", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(TS.Spacing.md)

            // Search bar
            searchBar

            // User list
            List {
                ForEach(filteredUsers) { user in
                    userRow(user)
                }
            }
            .listStyle(.inset)
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.labelTertiary)
            TextField("Zoek gebruiker...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoekveld wissen")
            }
        }
        .padding(TS.Spacing.sm)
        .background(Color.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: TS.Radius.sm)
                .stroke(Color.borderPrimary, lineWidth: 1)
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.bottom, TS.Spacing.sm)
    }

    private func userRow(_ user: AdminUser) -> some View {
        HStack(spacing: TS.Spacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.surfaceTertiary)
                    .frame(width: 44, height: 44)
                Text(String((user.name ?? user.email).prefix(1)).uppercased())
                    .font(TS.Font.title3Bold)
                    .foregroundStyle(Color.labelSecondary)
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: TS.Spacing.sm) {
                    Text(user.name ?? user.email)
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.labelPrimary)

                    Text(user.role.capitalized)
                        .font(TS.Font.microSemibold)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.surfaceTertiary)
                        .clipShape(Capsule())
                }
                if user.name != nil {
                    Text(user.email)
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            Spacer()

            // 2FA lock icon
            Image(systemName: "lock.open")
                .font(.system(size: 16))
                .foregroundStyle(Color.labelTertiary)

            // Context menu
            Menu {
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(user.email, forType: .string)
                    #else
                    UIPasteboard.general.string = user.email
                    #endif
                } label: {
                    Label("Kopieer e-mail", systemImage: "doc.on.doc")
                }

                if user.id != authVM.currentUser?.id {
                    Divider()
                    Button(role: .destructive) {
                        userToDelete = user
                        showDeleteConfirm = true
                    } label: {
                        Label("Verwijderen", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.labelTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Gebruikersopties")
        }
        .padding(.vertical, TS.Spacing.xs)
    }

    // MARK: - Uitnodigingen Tab

    private var uitnodigingenTab: some View {
        VStack(spacing: 0) {
            // Header with create button
            HStack {
                Spacer()
                Button {
                    newInviteMaxUses = 1
                    newInviteExpiresHours = 48
                    showCreateInvitationSheet = true
                } label: {
                    Label("Uitnodiging aanmaken", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(TS.Spacing.md)

            if invitations.isEmpty {
                Spacer()
                VStack(spacing: TS.Spacing.md) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.labelTertiary)
                    Text("Geen uitnodigingen")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(invitations) { invitation in
                        invitationRow(invitation)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func invitationRow(_ invitation: AdminInvitation) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "ticket.fill")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.brandPrimary)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.code)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.labelPrimary)
                HStack(spacing: TS.Spacing.sm) {
                    if let createdAt = invitation.createdAt {
                        Text(formattedDate(createdAt))
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.labelTertiary)
                    }
                    if let remaining = invitation.usesRemaining, let max = invitation.maxUses {
                        Text("\(remaining)/\(max) gebruikt")
                            .font(TS.Font.micro)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }

            Spacer()

            // Copy button
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(invitation.code, forType: .string)
                #else
                UIPasteboard.general.string = invitation.code
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Code kopiëren")

            // Status
            let isExpired = {
                guard let exp = invitation.expiresAt else { return false }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime]
                guard let date = iso.date(from: exp) else { return false }
                return date < Date()
            }()
            let remaining = invitation.usesRemaining ?? 1

            if remaining == 0 {
                Text("Opgebruikt")
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(Color.statusSuccess.opacity(0.12))
                    .foregroundStyle(Color.statusSuccess)
                    .clipShape(Capsule())
            } else if isExpired {
                Text("Verlopen")
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(Color.statusError.opacity(0.12))
                    .foregroundStyle(Color.statusError)
                    .clipShape(Capsule())
            } else {
                Text("Actief")
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(Color.brandOrange.opacity(0.12))
                    .foregroundStyle(Color.brandOrange)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, TS.Spacing.xs)
    }

    // MARK: - Feedback Tab

    private var filteredFeedbackItems: [AdminFeedback] {
        showArchivedFeedback ? feedbackItems : feedbackItems.filter { $0.status != "archived" }
    }

    private var feedbackTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Filter toggle
                HStack {
                    Text("\(filteredFeedbackItems.count) item\(filteredFeedbackItems.count == 1 ? "" : "s")")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Toggle("Toon gearchiveerd", isOn: $showArchivedFeedback)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(TS.Font.caption)
                }
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.sm)

                if filteredFeedbackItems.isEmpty {
                    VStack(spacing: TS.Spacing.md) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.labelTertiary)
                        Text("Geen feedback")
                            .font(TS.Font.callout)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, TS.Spacing.xxl)
                } else {
                    LazyVStack(spacing: TS.Spacing.md) {
                        ForEach(filteredFeedbackItems) { item in
                            feedbackCard(item)
                        }
                    }
                    .padding(TS.Spacing.md)
                }
            }
        }
    }

    private func feedbackCard(_ item: AdminFeedback) -> some View {
        let isArchived = item.status == "archived"
        return VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            // Top row: category + status badges
            HStack(spacing: TS.Spacing.sm) {
                Text(feedbackCategoryLabel(item.category))
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(feedbackCategoryColor(item.category).opacity(0.12))
                    .foregroundStyle(feedbackCategoryColor(item.category))
                    .clipShape(Capsule())

                Text(feedbackStatusLabel(item.status))
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(feedbackStatusColor(item.status).opacity(0.12))
                    .foregroundStyle(feedbackStatusColor(item.status))
                    .clipShape(Capsule())

                Spacer()

                if let createdAt = item.createdAt {
                    Text(formattedDate(createdAt))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            Text(item.title)
                .font(TS.Font.bodyMedium)
                .foregroundStyle(Color.labelPrimary)

            if !item.description.isEmpty {
                Text(item.description)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(3)
            }

            if let response = item.adminResponse, !response.isEmpty {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(TS.Font.micro)
                    Text(response)
                        .font(TS.Font.footnote)
                        .lineLimit(2)
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(TS.Spacing.sm)
                .background(Color.brandPrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
            }

            Divider()

            HStack(spacing: TS.Spacing.sm) {
                if isArchived {
                    feedbackStatusButton("Herstellen", targetStatus: "open", currentStatus: item.status, itemId: item.id)
                } else {
                    feedbackStatusButton("Nieuw", targetStatus: "new", currentStatus: item.status, itemId: item.id)
                    feedbackStatusButton("In behandeling", targetStatus: "in_progress", currentStatus: item.status, itemId: item.id)
                    feedbackStatusButton("Opgelost", targetStatus: "resolved", currentStatus: item.status, itemId: item.id)
                }
            }
        }
        .padding(TS.Spacing.md)
        .modernCard()
        .opacity(isArchived ? 0.6 : 1.0)
        .contextMenu {
            if isArchived {
                Button {
                    Task {
                        do {
                            try await APIService.shared.updateAdminFeedback(id: item.id, status: "open", response: nil)
                            _ = await loadFeedback()
                        } catch {
                            errorMessage = "Herstellen mislukt: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label("Herstellen", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    Task {
                        do {
                            try await APIService.shared.updateAdminFeedback(id: item.id, status: "archived", response: nil)
                            _ = await loadFeedback()
                        } catch {
                            errorMessage = "Archiveren mislukt: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label("Archiveren", systemImage: "archivebox")
                }
            }
            Divider()
            Button(role: .destructive) {
                feedbackToDelete = item
                showDeleteFeedbackConfirm = true
            } label: {
                Label("Verwijderen", systemImage: "trash")
            }
        }
    }

    private func feedbackStatusButton(_ label: String, targetStatus: String, currentStatus: String, itemId: String) -> some View {
        Button {
            Task {
                do {
                    try await APIService.shared.updateAdminFeedback(id: itemId, status: targetStatus, response: nil)
                    _ = await loadFeedback()
                } catch {
                    errorMessage = "Status bijwerken mislukt: \(error.localizedDescription)"
                }
            }
        } label: {
            Text(label)
                .font(TS.Font.micro)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .stroke(
                    currentStatus == targetStatus ? Color.brandPrimary : Color.borderPrimary,
                    lineWidth: 1
                )
        }
        .foregroundStyle(currentStatus == targetStatus ? Color.brandPrimary : Color.labelSecondary)
        .disabled(currentStatus == targetStatus)
    }

    // MARK: - Fouten Tab

    // MARK: - Logging Tab (Activity + Errors)

    private var foutenTab: some View {
        VStack(spacing: 0) {
            logFilterBar
            logContent
        }
        .onChange(of: logSubTab) { _, _ in
            logPage = 1
            expandedLogRow = nil
            Task { await reloadLogs() }
        }
        .onChange(of: logSeverityFilter) { _, _ in Task { await reloadLogs() } }
        .onChange(of: logUserFilter) { _, _ in Task { await reloadLogs() } }
        .onChange(of: logTypeFilter) { _, _ in Task { await reloadLogs() } }
    }

    private var logFilterBar: some View {
        VStack(spacing: TS.Spacing.sm) {
            // Sub-tab toggle — native segmented control with live counts
            HStack(spacing: TS.Spacing.sm) {
                Picker("Logtype", selection: $logSubTab) {
                    ForEach(LogSubTab.allCases, id: \.self) { tab in
                        let count = tab == .activity ? activityLogs.count : errors.count
                        Text(count > 0 ? "\(tab.rawValue) (\(count))" : tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                Spacer()
                if isLoadingLogs {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.xs)
            .background(Color.surfaceSecondary)

            // Filter row
            HStack(spacing: TS.Spacing.sm) {
                // Search field
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.labelTertiary)
                    TextField(logSubTab == .activity ? "Zoek op gebruiker, actie..." : "Zoek op foutmelding, endpoint...", text: $logSearch)
                        .font(TS.Font.footnote)
                        .textFieldStyle(.plain)
                        .onSubmit { Task { await reloadLogs() } }
                    if !logSearch.isEmpty {
                        Button {
                            logSearch = ""
                            Task { await reloadLogs() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(TS.Font.micro)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, 5)
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                .frame(maxWidth: 260)

                if logSubTab == .errors {
                    // Severity filter
                    Picker("", selection: $logSeverityFilter) {
                        Text("Alle niveaus").tag("")
                        Text("Error").tag("error")
                        Text("Warning").tag("warning")
                        Text("Info").tag("info")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                } else {
                    // Action type filter
                    Picker("", selection: $logTypeFilter) {
                        Text("Alle acties").tag("")
                        Text("Login").tag("login")
                        Text("Upload").tag("upload_complete")
                        Text("Transcriptie").tag("transcription_complete")
                        Text("Notule").tag("note_create")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                // User filter
                if !users.isEmpty {
                    Picker("", selection: $logUserFilter) {
                        Text("Alle gebruikers").tag("")
                        ForEach(users) { user in
                            Text(user.name ?? user.email).tag(user.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                Spacer()

                if hasLogFilters {
                    Button("Wis filters") {
                        clearLogFilters()
                        Task { await reloadLogs() }
                    }
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.xs)
        }
    }

    private var hasLogFilters: Bool {
        !logSearch.isEmpty || !logSeverityFilter.isEmpty || !logUserFilter.isEmpty || !logTypeFilter.isEmpty
    }

    private func clearLogFilters() {
        logSearch = ""
        logSeverityFilter = ""
        logUserFilter = ""
        logTypeFilter = ""
        logPage = 1
    }

    @ViewBuilder
    private var logContent: some View {
        let currentData: [Any] = logSubTab == .activity ? activityLogs as [Any] : errors as [Any]
        let totalItems = currentData.count
        let totalPages = max(1, Int(ceil(Double(totalItems) / Double(logPageSize))))
        let safePage = min(logPage, totalPages)
        let startIdx = (safePage - 1) * logPageSize
        let endIdx = min(startIdx + logPageSize, totalItems)

        if totalItems == 0 && !isLoadingLogs {
            VStack(spacing: TS.Spacing.md) {
                Image(systemName: logSubTab == .activity ? "clock" : "checkmark.shield")
                    .font(.system(size: 36))
                    .foregroundStyle(logSubTab == .activity ? Color.labelTertiary : Color.statusSuccess)
                Text(hasLogFilters
                     ? "Geen resultaten voor deze filters"
                     : logSubTab == .activity
                     ? "Geen activiteit gevonden"
                     : "Geen fouten gevonden. Het systeem draait normaal.")
                    .font(TS.Font.callout)
                    .foregroundStyle(Color.labelSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, TS.Spacing.xxl)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Table header
                    logTableHeader

                    // Rows
                    if logSubTab == .activity {
                        let pageItems = Array(activityLogs[startIdx..<endIdx])
                        ForEach(Array(pageItems.enumerated()), id: \.offset) { idx, entry in
                            let globalIdx = startIdx + idx
                            activityRow(entry, index: globalIdx)
                        }
                    } else {
                        let pageItems = Array(errors[startIdx..<endIdx])
                        ForEach(Array(pageItems.enumerated()), id: \.offset) { idx, entry in
                            let globalIdx = startIdx + idx
                            errorRow(entry, index: globalIdx)
                        }
                    }
                }

                // Pagination
                if totalPages > 1 {
                    logPagination(page: safePage, totalPages: totalPages, totalItems: totalItems, startIdx: startIdx, endIdx: endIdx)
                }
            }
        }
    }

    private var logTableHeader: some View {
        HStack(spacing: 0) {
            if logSubTab == .activity {
                Text("Tijd").frame(width: 130, alignment: .leading)
                Text("Gebruiker").frame(width: 140, alignment: .leading)
                Text("Actie").frame(width: 130, alignment: .leading)
                Text("Endpoint").frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tijd").frame(width: 130, alignment: .leading)
                Text("Ernst").frame(width: 80, alignment: .leading)
                Text("Type").frame(width: 120, alignment: .leading)
                Text("Endpoint").frame(width: 180, alignment: .leading)
                Text("Foutmelding").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(TS.Font.captionSemibold)
        .foregroundStyle(Color.labelSecondary)
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
        .background(Color.surfaceSecondary)
    }

    private func activityRow(_ entry: AdminActivity, index: Int) -> some View {
        let isExpanded = expandedLogRow == index
        return VStack(spacing: 0) {
            Button {
                withAnimation(TS.Animation.smooth) {
                    expandedLogRow = isExpanded ? nil : index
                }
            } label: {
                HStack(spacing: 0) {
                    Text(logTimestamp(entry.createdAt))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                        .frame(width: 130, alignment: .leading)
                    Text(entry.username ?? "Systeem")
                        .font(TS.Font.footnoteSemibold)
                        .foregroundStyle(Color.labelPrimary)
                        .frame(width: 140, alignment: .leading)
                        .lineLimit(1)
                    activityBadge(entry.actionType)
                        .frame(width: 130, alignment: .leading)
                    Text(entry.endpoint ?? "-")
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.sm)
                .background(isExpanded ? Color.surfaceSecondary : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                activityDetail(entry)
            }

            Divider()
        }
    }

    private func activityBadge(_ actionType: String) -> some View {
        let label = activityLabel(actionType)
        let color = activityBadgeColor(actionType)
        return Text(label)
            .font(TS.Font.microSemibold)
            .padding(.horizontal, TS.Spacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func activityLabel(_ type: String) -> String {
        let labels: [String: String] = [
            "login": "Ingelogd", "logout": "Uitgelogd", "login_failed": "Login mislukt",
            "upload_complete": "Upload", "transcription_complete": "Transcriptie",
            "transcription_error": "Transcriptie fout", "note_create": "Notule aangemaakt",
            "note_delete": "Notule verwijderd", "note_download": "Notule download",
            "feedback_submitted": "Feedback", "admin_user_create": "Gebruiker aangemaakt",
            "admin_user_delete": "Gebruiker verwijderd", "admin_password_reset": "Wachtwoord reset",
        ]
        if let mapped = labels[type.lowercased()] { return mapped }
        // Humanise unknown action types instead of leaking the raw snake_case key.
        let humanised = type.replacingOccurrences(of: "_", with: " ")
        return humanised.isEmpty ? type : humanised.prefix(1).uppercased() + humanised.dropFirst()
    }

    private func activityBadgeColor(_ type: String) -> Color {
        let t = type.lowercased()
        if t.contains("login") || t.contains("logout") { return .purple }
        if t.contains("upload") || t.contains("transcri") { return Color.brandPrimary }
        if t.contains("delet") { return Color.statusError }
        if t.contains("creat") || t.contains("generat") { return Color.statusSuccess }
        if t.contains("error") || t.contains("fail") { return Color.brandOrange }
        return Color.labelSecondary
    }

    private func activityDetail(_ entry: AdminActivity) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            if let details = entry.details, !details.isEmpty {
                logDetailRow("Details", details)
            }
            if let ip = entry.ipAddress, !ip.isEmpty {
                logDetailRow("IP", ip, mono: true)
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.surfaceTertiary)
    }

    private func errorRow(_ entry: AdminError, index: Int) -> some View {
        let isExpanded = expandedLogRow == index
        let sevColor = errorSeverityColor(entry)
        return VStack(spacing: 0) {
            Button {
                withAnimation(TS.Animation.smooth) {
                    expandedLogRow = isExpanded ? nil : index
                }
            } label: {
                HStack(spacing: 0) {
                    Text(logTimestamp(entry.createdAt))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                        .frame(width: 130, alignment: .leading)
                    Text((entry.severity ?? "error").uppercased())
                        .font(.system(size: 9, weight: .bold, design: .default))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sevColor.opacity(0.15))
                        .foregroundStyle(sevColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(width: 80, alignment: .leading)
                    Text(entry.errorType ?? "Unknown")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)
                    Text(entry.endpoint ?? "-")
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)
                    Text(entry.errorMessage ?? "Onbekende fout")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, TS.Spacing.md)
                .padding(.vertical, TS.Spacing.sm)
                .background(isExpanded ? Color.surfaceSecondary : Color.clear)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(sevColor)
                        .frame(width: 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                errorDetail(entry)
            }

            Divider()
        }
    }

    private func errorSeverityColor(_ adminError: AdminError) -> Color {
        let severity = (adminError.severity ?? adminError.errorType ?? "error").lowercased()
        switch severity {
        case "critical": return Color.statusError
        case "warning":  return Color.brandOrange
        case "info":     return Color.brandPrimary
        default:         return Color.statusError
        }
    }

    private func errorDetail(_ entry: AdminError) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            if let msg = entry.errorMessage, !msg.isEmpty {
                logDetailRow("Foutmelding", msg)
            }
            if let detail = entry.errorDetail, !detail.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DETAIL")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.labelTertiary)
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.labelPrimary)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(TS.Spacing.sm)
                    .background(Color.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: TS.Radius.sm)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
                }
            }
            HStack(spacing: TS.Spacing.lg) {
                if let code = entry.statusCode {
                    logDetailRow("Status", "\(code)", mono: true)
                }
                if let method = entry.method, !method.isEmpty {
                    logDetailRow("Methode", method.uppercased(), mono: true)
                }
                if let user = entry.username ?? entry.userId, !user.isEmpty {
                    logDetailRow("Gebruiker", user)
                }
            }
        }
        .padding(TS.Spacing.md)
        .background(Color.surfaceTertiary)
    }

    private func logDetailRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.labelTertiary)
            Text(value)
                .font(mono ? TS.Font.captionMonospaced : TS.Font.caption)
                .foregroundStyle(Color.labelPrimary)
                .textSelection(.enabled)
        }
    }

    private func logPagination(page: Int, totalPages: Int, totalItems: Int, startIdx: Int, endIdx: Int) -> some View {
        HStack {
            Text("\(startIdx + 1)–\(endIdx) van \(totalItems)")
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)
            Spacer()
            HStack(spacing: TS.Spacing.sm) {
                Button {
                    logPage = max(1, logPage - 1)
                    expandedLogRow = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(TS.Font.caption)
                }
                .disabled(page <= 1)
                .buttonStyle(.plain)

                Text("Pagina \(page) van \(totalPages)")
                    .font(TS.Font.captionSemibold)
                    .foregroundStyle(Color.labelPrimary)

                Button {
                    logPage = min(totalPages, logPage + 1)
                    expandedLogRow = nil
                } label: {
                    Image(systemName: "chevron.right")
                        .font(TS.Font.caption)
                }
                .disabled(page >= totalPages)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
    }

    private func logTimestamp(_ dateString: String?) -> String {
        guard let dateString else { return "-" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: dateString)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: dateString)
        }
        guard let date else { return dateString.prefix(16).description }
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "nl_NL")
        df.timeStyle = .short
        if cal.isDateInToday(date) {
            return "Vandaag \(df.string(from: date))"
        } else if cal.isDateInYesterday(date) {
            return "Gisteren \(df.string(from: date))"
        }
        df.dateFormat = "d MMM HH:mm"
        return df.string(from: date)
    }

    private func reloadLogs() async {
        isLoadingLogs = true
        expandedLogRow = nil
        do {
            if logSubTab == .activity {
                activityLogs = try await APIService.shared.getAdminActivity(
                    limit: 500,
                    userId: logUserFilter.isEmpty ? nil : logUserFilter,
                    actionType: logTypeFilter.isEmpty ? nil : logTypeFilter,
                    search: logSearch.isEmpty ? nil : logSearch
                )
            } else {
                errors = try await APIService.shared.getAdminErrors(
                    limit: 500,
                    severity: logSeverityFilter.isEmpty ? nil : logSeverityFilter,
                    userId: logUserFilter.isEmpty ? nil : logUserFilter,
                    search: logSearch.isEmpty ? nil : logSearch
                )
            }
        } catch {
            DebugLogger.shared.error(error, context: "Logs laden", category: "Admin")
        }
        isLoadingLogs = false
    }

    // MARK: - Instellingen Tab

    private var instellingenTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TS.Spacing.lg) {
                // Microsoft 365 OAuth section
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.brandPrimary)
                        Text("Microsoft 365 Agenda")
                            .font(TS.Font.title3Bold)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Text("Configureer OAuth credentials zodat gebruikers hun Microsoft 365 agenda kunnen koppelen. Maak een App Registration aan in Azure Portal met redirect URI: transcript-studio://auth/callback")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Client ID")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $ms365ClientId)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Tenant ID")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $ms365TenantId)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }

                    HStack(spacing: TS.Spacing.md) {
                        Button {
                            Task { await saveAdminSettings() }
                        } label: {
                            HStack(spacing: TS.Spacing.xs) {
                                if isLoadingSettings {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Opslaan")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoadingSettings)

                        if showSettingsSaved {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Opgeslagen")
                            }
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusSuccess)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(TS.Spacing.md)
                .modernCard()

                // Google OAuth section
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.red)
                        Text("Google OAuth (YouTube)")
                            .font(TS.Font.title3Bold)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Text("Configureer Google OAuth credentials zodat gebruikers YouTube video's kunnen transcriberen via de Captions API. Maak een OAuth Client ID aan in Google Cloud Console met redirect URI: transcript-studio://google/callback")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Client ID (macOS)")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("xxxxxxxx.apps.googleusercontent.com", text: $googleOAuthClientIdMacos)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Client ID (Windows)")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("xxxxxxxx.apps.googleusercontent.com", text: $googleOAuthClientIdWindows)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }
                }
                .padding(TS.Spacing.md)
                .modernCard()

                // YouTube settings section
                VStack(alignment: .leading, spacing: TS.Spacing.md) {
                    HStack(spacing: TS.Spacing.sm) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.red)
                        Text("YouTube Instellingen")
                            .font(TS.Font.title3Bold)
                            .foregroundStyle(Color.labelPrimary)
                    }

                    Text("Configureer hoe yt-dlp YouTube video's downloadt. Standaard wordt de web client gebruikt met PO token authenticatie.")
                        .font(TS.Font.footnote)
                        .foregroundStyle(Color.labelSecondary)

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Maximale videoduur (minuten)")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("120", text: $youtubeMaxDurationMinutes)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .frame(width: 120)
                    }

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("yt-dlp Extractor Args")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("youtube:player_client=web;fetch_pot=always", text: $youtubeExtractorArgs)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Proxy (optioneel)")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        Text("SOCKS5 of HTTP proxy om YouTube IP-blokkades te omzeilen. Voorbeeld: socks5://user:pass@host:port")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                        TextField("socks5://host:port", text: $youtubeProxy)
                            .textFieldStyle(.roundedBorder)
                            .font(TS.Font.body)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                        Text("Cookies (optioneel)")
                            .font(TS.Font.footnoteSemibold)
                            .foregroundStyle(Color.labelSecondary)
                        Text("Plak Netscape-formaat cookies voor video's die anoniem niet beschikbaar zijn.")
                            .font(TS.Font.caption)
                            .foregroundStyle(Color.labelTertiary)
                        TextEditor(text: $youtubeCookiesContent)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 80, maxHeight: 160)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TS.Radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: TS.Radius.sm)
                                    .stroke(Color.borderPrimary, lineWidth: 1)
                            )
                    }

                    HStack(spacing: TS.Spacing.md) {
                        Button {
                            Task { await saveAdminSettings() }
                        } label: {
                            HStack(spacing: TS.Spacing.xs) {
                                if isLoadingSettings {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Opslaan")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoadingSettings)

                        if showSettingsSaved {
                            HStack(spacing: TS.Spacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Opgeslagen")
                            }
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.statusSuccess)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .padding(TS.Spacing.md)
                .modernCard()
            }
            .padding(TS.Spacing.md)
        }
        .task {
            await loadAdminSettings()
        }
    }

    private func loadAdminSettings() async {
        do {
            let settings = try await APIService.shared.getAdminSettings()
            ms365ClientId = settings.ms365_client_id ?? ""
            ms365TenantId = settings.ms365_tenant_id ?? ""
            googleOAuthClientIdMacos = settings.google_oauth_client_id_macos ?? ""
            googleOAuthClientIdWindows = settings.google_oauth_client_id_windows ?? ""
            youtubeMaxDurationMinutes = settings.youtube_max_duration_minutes.map { String($0) } ?? "120"
            youtubeCookiesContent = settings.youtube_cookies_content ?? ""
            youtubeExtractorArgs = settings.youtube_extractor_args ?? "youtube:player_client=web;fetch_pot=always"
            youtubeProxy = settings.youtube_proxy ?? ""
        } catch {
            DebugLogger.shared.error(error, context: "Instellingen laden", category: "Admin")
        }
    }

    private func saveAdminSettings() async {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        do {
            try await APIService.shared.updateAdminSettings(
                ms365ClientId: ms365ClientId,
                ms365TenantId: ms365TenantId,
                googleOAuthClientIdMacos: googleOAuthClientIdMacos,
                googleOAuthClientIdWindows: googleOAuthClientIdWindows,
                youtubeMaxDurationMinutes: Int(youtubeMaxDurationMinutes),
                youtubeCookiesContent: youtubeCookiesContent,
                youtubeExtractorArgs: youtubeExtractorArgs,
                youtubeProxy: youtubeProxy
            )
            withAnimation(TS.Animation.quick) {
                showSettingsSaved = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(TS.Animation.quick) {
                    showSettingsSaved = false
                }
            }
        } catch {
            errorMessage = "Instellingen opslaan mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: - Create User Sheet

    private var createUserSheet: some View {
        VStack(spacing: TS.Spacing.lg) {
            Text("Nieuwe gebruiker")
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("E-mailadres")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                TextField("gebruiker@voorbeeld.nl", text: $newUserEmail)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Wachtwoord")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                SecureField("Minimaal 8 tekens", text: $newUserPassword)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Naam (optioneel)")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                TextField("Volledige naam", text: $newUserName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Rol")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Picker("Rol", selection: $newUserRole) {
                    Text("User").tag("user")
                    Text("Admin").tag("admin")
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: TS.Spacing.md) {
                Button("Annuleer") {
                    showCreateUserSheet = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Aanmaken") {
                    Task {
                        do {
                            try await APIService.shared.createUser(
                                email: newUserEmail,
                                password: newUserPassword,
                                name: newUserName.isEmpty ? nil : newUserName,
                                role: newUserRole
                            )
                            showCreateUserSheet = false
                            _ = await loadUsers()
                        } catch {
                            errorMessage = "Aanmaken mislukt: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newUserEmail.isEmpty || newUserPassword.isEmpty)
            }
        }
        .padding(TS.Spacing.xl)
        .frame(minWidth: 380)
    }

    // MARK: - Create Invitation Sheet

    private var createInvitationSheet: some View {
        VStack(spacing: TS.Spacing.lg) {
            Text("Nieuwe uitnodigingscode")
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Maximaal gebruik")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Stepper("\(newInviteMaxUses)x", value: $newInviteMaxUses, in: 1...100)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Geldig voor")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Picker("Geldigheid", selection: $newInviteExpiresHours) {
                    Text("24 uur").tag(24)
                    Text("48 uur").tag(48)
                    Text("7 dagen").tag(168)
                    Text("30 dagen").tag(720)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: TS.Spacing.md) {
                Button("Annuleer") {
                    showCreateInvitationSheet = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Aanmaken") {
                    Task {
                        do {
                            try await APIService.shared.createInvitation(
                                maxUses: newInviteMaxUses,
                                expiresHours: newInviteExpiresHours
                            )
                            showCreateInvitationSheet = false
                            _ = await loadInvitations()
                        } catch {
                            errorMessage = "Uitnodiging mislukt: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(TS.Spacing.xl)
        .frame(minWidth: 380)
    }

    // MARK: - Helpers

    private func roleColor(_ role: String) -> Color {
        switch role.lowercased() {
        case "admin": return Color.brandPrimary
        case "user":  return Color.brandSecondary
        default:      return Color.labelTertiary
        }
    }

    private func feedbackCategoryLabel(_ category: String) -> String {
        switch category.lowercased() {
        case "bug":     return "Bug"
        case "feature": return "Feature"
        case "general": return "Algemeen"
        default:        return category.capitalized
        }
    }

    private func feedbackCategoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "bug":     return Color.statusError
        case "feature": return Color.statusSuccess
        case "general": return Color.brandOrange
        default:        return Color.labelTertiary
        }
    }

    private func feedbackStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "new":         return "Nieuw"
        case "in_progress": return "In behandeling"
        case "resolved":    return "Opgelost"
        case "archived":    return "Gearchiveerd"
        default:            return status.capitalized
        }
    }

    private func feedbackStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "new":         return Color.brandPrimary
        case "in_progress": return Color.brandOrange
        case "resolved":    return Color.statusSuccess
        case "archived":    return Color.labelTertiary
        default:            return Color.labelTertiary
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: dateString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "nl_NL")
            df.dateStyle = .medium
            return df.string(from: date)
        }
        // Try without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "nl_NL")
            df.dateStyle = .medium
            return df.string(from: date)
        }
        return dateString
    }

    // MARK: - Data Operations

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        var failedSections: [String] = []

        async let statsResult = loadStats()
        async let usersResult = loadUsers()
        async let invitationsResult = loadInvitations()
        async let bugReportsResult = loadFeedback()
        async let errorsResult = loadErrors()
        async let activityResult = loadActivityLogs()

        let results = await [statsResult, usersResult, invitationsResult, bugReportsResult, errorsResult, activityResult]
        failedSections = results.compactMap { $0 }

        if failedSections.count == results.count {
            errorMessage = "Kan geen verbinding maken met de backend."
        } else if !failedSections.isEmpty {
            errorMessage = "Kon niet laden: \(failedSections.joined(separator: ", "))"
        }

        isLoading = false
    }

    private func loadStats() async -> String? {
        do {
            stats = try await APIService.shared.getAdminStats()
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Stats laden", category: "Admin")
            return "statistieken"
        }
    }

    private func loadUsers() async -> String? {
        do {
            users = try await APIService.shared.getAdminUsers()
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Gebruikers laden", category: "Admin")
            return "gebruikers"
        }
    }

    private func loadInvitations() async -> String? {
        do {
            invitations = try await APIService.shared.getAdminInvitations()
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Uitnodigingen laden", category: "Admin")
            return "uitnodigingen"
        }
    }

    private func loadFeedback() async -> String? {
        do {
            feedbackItems = try await APIService.shared.getAdminFeedback()
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Feedback laden", category: "Admin")
            return "feedback"
        }
    }

    private func loadErrors() async -> String? {
        do {
            errors = try await APIService.shared.getAdminErrors(limit: 500)
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Fouten laden", category: "Admin")
            return "fouten"
        }
    }

    private func loadActivityLogs() async -> String? {
        do {
            activityLogs = try await APIService.shared.getAdminActivity(limit: 500)
            return nil
        } catch {
            DebugLogger.shared.error(error, context: "Activiteit laden", category: "Admin")
            return "activiteit"
        }
    }

    private func deleteUser(_ user: AdminUser) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIService.shared.deleteUser(id: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = "Verwijderen mislukt: \(error.localizedDescription)"
        }
    }

    private func deleteFeedback(_ item: AdminFeedback) async {
        do {
            try await APIService.shared.deleteAdminFeedback(id: item.id)
            feedbackItems.removeAll { $0.id == item.id }
        } catch {
            errorMessage = "Feedback verwijderen mislukt: \(error.localizedDescription)"
        }
    }
}

// MARK: - Admin Models

struct AdminStats: Codable {
    let totalUsers: Int
    let totalNotes: Int
    let transcriptionsToday: Int
    let errors7d: Int

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case totalNotes = "total_notes"
        case transcriptionsToday = "transcriptions_today"
        case errors7d = "errors_7d"
    }
}

struct AdminInvitation: Codable, Identifiable {
    var id: String { code }
    let code: String
    let createdBy: String?
    let usesRemaining: Int?
    let maxUses: Int?
    let expiresAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case code
        case createdBy = "created_by"
        case usesRemaining = "uses_remaining"
        case maxUses = "max_uses"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct AdminFeedback: Codable, Identifiable {
    let id: String
    let category: String
    let status: String
    let title: String
    let description: String
    let userId: String?
    let username: String?
    let createdAt: String?
    let updatedAt: String?
    let adminResponse: String?
    let adminUserId: String?
    let resolvedAt: String?
    let responseReadAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, status, title, description, username
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case adminResponse = "admin_response"
        case adminUserId = "admin_user_id"
        case resolvedAt = "resolved_at"
        case responseReadAt = "response_read_at"
    }
}

struct AdminError: Codable, Identifiable {
    let id: String
    let errorType: String?
    let endpoint: String?
    let method: String?
    let errorMessage: String?
    let errorDetail: String?
    let statusCode: Int?
    let severity: String?
    let userId: String?
    let username: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, endpoint, method, severity, username
        case errorType = "error_type"
        case errorMessage = "error_message"
        case errorDetail = "error_detail"
        case statusCode = "status_code"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct AdminActivity: Codable, Identifiable {
    let id: String
    let actionType: String
    let userId: String?
    let username: String?
    let endpoint: String?
    let details: String?
    let ipAddress: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, endpoint, details
        case actionType = "action_type"
        case userId = "user_id"
        case ipAddress = "ip_address"
        case createdAt = "created_at"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AdminView()
            .environment(AuthViewModel())
    }
    .frame(width: 700, height: 600)
}
