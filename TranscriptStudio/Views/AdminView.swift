// AdminView.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
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

// MARK: - AdminView

struct AdminView: View {

    @Environment(AuthViewModel.self) var authVM
    @Namespace private var tabNamespace

    @State private var selectedTab: AdminTab = .overzicht
    @State private var users: [AdminUser] = []
    @State private var stats: AdminStats? = nil
    @State private var invitations: [AdminInvitation] = []
    @State private var feedbackItems: [AdminFeedback] = []
    @State private var errors: [AdminError] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""
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

    // Create invitation form
    @State private var newInviteMaxUses = 1
    @State private var newInviteExpiresHours = 48

    // Admin settings
    @State private var ms365ClientId = ""
    @State private var ms365TenantId = ""
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.lg) {
                ForEach(AdminTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
        }
        .background(Color.surfaceSecondary)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabButton(_ tab: AdminTab) -> some View {
        Button {
            withAnimation(TS.Animation.smooth) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: TS.Spacing.xs) {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: tab.icon)
                        .font(TS.Font.footnote)
                    Text(tab.rawValue)
                        .font(TS.Font.footnoteSemibold)
                }
                .foregroundStyle(selectedTab == tab ? Color.brandPrimary : Color.labelSecondary)
                .padding(.horizontal, TS.Spacing.xs)

                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)

                    if selectedTab == tab {
                        Rectangle()
                            .fill(Color.brandPrimary)
                            .frame(height: 2)
                            .matchedGeometryEffect(id: "tab_indicator", in: tabNamespace)
                    }
                }
            }
        }
        .buttonStyle(.plain)
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
                        value: "\(stats?.totalTranscripts ?? 0)",
                        label: "Notulen",
                        icon: "doc.text.fill",
                        color: Color.statusSuccess
                    )
                    statCard(
                        value: "\(stats?.totalTasks ?? 0)",
                        label: "Taken totaal",
                        icon: "checklist",
                        color: Color.brandOrange
                    )
                    statCard(
                        value: "\(stats?.errors24h ?? 0)",
                        label: "Fouten (24u)",
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
                .font(.system(size: 36, weight: .bold, design: .rounded))
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
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }
            .buttonStyle(.plain)

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

    private var feedbackTab: some View {
        ScrollView {
            if feedbackItems.isEmpty {
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
                    ForEach(feedbackItems) { item in
                        feedbackCard(item)
                    }
                }
                .padding(TS.Spacing.md)
            }
        }
    }

    private func feedbackCard(_ item: AdminFeedback) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
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

            if let response = item.response, !response.isEmpty {
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
                feedbackStatusButton("Nieuw", targetStatus: "new", currentStatus: item.status, itemId: item.id)
                feedbackStatusButton("In behandeling", targetStatus: "in_progress", currentStatus: item.status, itemId: item.id)
                feedbackStatusButton("Opgelost", targetStatus: "resolved", currentStatus: item.status, itemId: item.id)
            }
        }
        .padding(TS.Spacing.md)
        .modernCard()
    }

    private func feedbackStatusButton(_ label: String, targetStatus: String, currentStatus: String, itemId: String) -> some View {
        Button {
            Task {
                do {
                    try await APIService.shared.updateAdminFeedback(id: itemId, status: targetStatus, response: nil)
                    await loadFeedback()
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

    private var foutenTab: some View {
        ScrollView {
            if errors.isEmpty {
                VStack(spacing: TS.Spacing.md) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.statusSuccess)
                    Text("Geen fouten gevonden")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, TS.Spacing.xxl)
            } else {
                LazyVStack(spacing: TS.Spacing.md) {
                    ForEach(errors) { error in
                        errorCard(error)
                    }
                }
                .padding(TS.Spacing.md)
            }
        }
    }

    private func errorCard(_ adminError: AdminError) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            // Type badge + timestamp
            HStack {
                Text(adminError.type ?? "Error")
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(Color.statusError.opacity(0.12))
                    .foregroundStyle(Color.statusError)
                    .clipShape(Capsule())

                Spacer()

                if let createdAt = adminError.createdAt {
                    Text(formattedDate(createdAt))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            // Endpoint
            if let endpoint = adminError.endpoint, !endpoint.isEmpty {
                Text(endpoint)
                    .font(TS.Font.footnoteMonospaced)
                    .foregroundStyle(Color.labelPrimary)
            }

            // Error message
            Text(adminError.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(4)

            // Reporter
            if let reporter = adminError.userId, !reporter.isEmpty {
                HStack(spacing: TS.Spacing.xs) {
                    Image(systemName: "person")
                        .font(TS.Font.micro)
                    Text(reporter)
                        .font(TS.Font.caption)
                }
                .foregroundStyle(Color.labelTertiary)
            }
        }
        .padding(TS.Spacing.md)
        .modernCard()
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
                ms365TenantId: ms365TenantId
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
                            await loadUsers()
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
                            await loadInvitations()
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
        default:            return status.capitalized
        }
    }

    private func feedbackStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "new":         return Color.brandPrimary
        case "in_progress": return Color.brandOrange
        case "resolved":    return Color.statusSuccess
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

        async let statsResult: () = loadStats()
        async let usersResult: () = loadUsers()
        async let invitationsResult: () = loadInvitations()
        async let bugReportsResult: () = loadFeedback()
        async let errorsResult: () = loadErrors()

        _ = await (statsResult, usersResult, invitationsResult, bugReportsResult, errorsResult)
        isLoading = false
    }

    private func loadStats() async {
        do {
            stats = try await APIService.shared.getAdminStats()
        } catch {
            DebugLogger.shared.error(error, context: "Stats laden", category: "Admin")
        }
    }

    private func loadUsers() async {
        do {
            users = try await APIService.shared.getAdminUsers()
        } catch {
            DebugLogger.shared.error(error, context: "Gebruikers laden", category: "Admin")
        }
    }

    private func loadInvitations() async {
        do {
            invitations = try await APIService.shared.getAdminInvitations()
        } catch {
            DebugLogger.shared.error(error, context: "Uitnodigingen laden", category: "Admin")
        }
    }

    private func loadFeedback() async {
        do {
            feedbackItems = try await APIService.shared.getAdminFeedback()
        } catch {
            DebugLogger.shared.error(error, context: "Feedback laden", category: "Admin")
        }
    }

    private func loadErrors() async {
        do {
            errors = try await APIService.shared.getAdminErrors()
        } catch {
            DebugLogger.shared.error(error, context: "Fouten laden", category: "Admin")
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
}

// MARK: - Admin Models

struct AdminStats: Codable {
    let totalUsers: Int
    let totalTranscripts: Int
    let totalTasks: Int
    let errors24h: Int

    enum CodingKeys: String, CodingKey {
        case totalUsers = "total_users"
        case totalTranscripts = "total_transcripts"
        case totalTasks = "total_tasks"
        case errors24h = "errors_24h"
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
    let createdAt: String?
    let response: String?

    enum CodingKeys: String, CodingKey {
        case id, category, status, title, description, response
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct AdminError: Codable, Identifiable {
    let id: String
    let type: String?
    let endpoint: String?
    let message: String
    let severity: String?
    let userId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, endpoint, message, severity
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct AdminActivity: Codable, Identifiable {
    let id: String
    let actionType: String
    let userId: String?
    let details: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case actionType = "action_type"
        case userId = "user_id"
        case details
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
