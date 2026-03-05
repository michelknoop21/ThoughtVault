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
    case bugRapporten = "Bug Rapporten"
    case fouten = "Fouten"

    var icon: String {
        switch self {
        case .overzicht: return "chart.bar.fill"
        case .gebruikers: return "person.2.fill"
        case .uitnodigingen: return "envelope.fill"
        case .bugRapporten: return "ladybug.fill"
        case .fouten: return "exclamationmark.triangle.fill"
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
    @State private var bugReports: [AdminBugReport] = []
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
    @State private var newUserName = ""
    @State private var newUserRole = "user"

    // Create invitation form
    @State private var newInvitationEmail = ""
    @State private var newInvitationRole = "user"

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
            case .bugRapporten:
                bugRapportenTab
            case .fouten:
                foutenTab
            }
        }
    }

    // MARK: - Overzicht Tab

    private var overzichtTab: some View {
        ScrollView {
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
                    label: "Fouten 24u",
                    icon: "exclamationmark.triangle.fill",
                    color: Color.statusError
                )
            }
            .padding(TS.Spacing.md)
        }
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: TS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(TS.Font.title2Bold)
                .foregroundStyle(Color.labelPrimary)
            Text(label)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(TS.Spacing.md)
        .modernCard()
    }

    // MARK: - Gebruikers Tab

    private var gebruikersTab: some View {
        VStack(spacing: 0) {
            // Header with create button
            HStack {
                Spacer()
                Button {
                    newUserEmail = ""
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
        HStack(spacing: TS.Spacing.sm) {
            // Avatar
            ZStack {
                Circle()
                    .fill(roleColor(user.role).opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(String((user.name ?? user.email).prefix(1)).uppercased())
                    .font(TS.Font.headlineBold)
                    .foregroundStyle(roleColor(user.role))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                if let name = user.name, !name.isEmpty {
                    Text(name)
                        .font(TS.Font.bodyMedium)
                        .foregroundStyle(Color.labelPrimary)
                }
                Text(user.email)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            // Role badge
            Text(user.role.capitalized)
                .font(TS.Font.microSemibold)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
                .background(roleColor(user.role).opacity(0.12))
                .foregroundStyle(roleColor(user.role))
                .clipShape(Capsule())

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
                Image(systemName: "ellipsis")
                    .font(TS.Font.body)
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                    newInvitationEmail = ""
                    newInvitationRole = "user"
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
                Image(systemName: "envelope.fill")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.brandPrimary)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.email)
                    .font(TS.Font.bodyMedium)
                    .foregroundStyle(Color.labelPrimary)
                if let createdAt = invitation.createdAt {
                    Text("Verstuurd: \(formattedDate(createdAt))")
                        .font(TS.Font.micro)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            Spacer()

            // Role badge
            Text(invitation.role.capitalized)
                .font(TS.Font.microSemibold)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
                .background(roleColor(invitation.role).opacity(0.12))
                .foregroundStyle(roleColor(invitation.role))
                .clipShape(Capsule())

            // Status indicator
            if invitation.usedAt != nil {
                Text("Gebruikt")
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(Color.statusSuccess.opacity(0.12))
                    .foregroundStyle(Color.statusSuccess)
                    .clipShape(Capsule())
            } else {
                Text("Openstaand")
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

    // MARK: - Bug Rapporten Tab

    private var bugRapportenTab: some View {
        ScrollView {
            if bugReports.isEmpty {
                VStack(spacing: TS.Spacing.md) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.labelTertiary)
                    Text("Geen bug rapporten")
                        .font(TS.Font.callout)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, TS.Spacing.xxl)
            } else {
                LazyVStack(spacing: TS.Spacing.md) {
                    ForEach(bugReports) { report in
                        bugReportCard(report)
                    }
                }
                .padding(TS.Spacing.md)
            }
        }
    }

    private func bugReportCard(_ report: AdminBugReport) -> some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            // Top row: category + status badges
            HStack(spacing: TS.Spacing.sm) {
                // Category badge
                Text(bugCategoryLabel(report.category))
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(bugCategoryColor(report.category).opacity(0.12))
                    .foregroundStyle(bugCategoryColor(report.category))
                    .clipShape(Capsule())

                // Status badge
                Text(bugStatusLabel(report.status))
                    .font(TS.Font.microSemibold)
                    .padding(.horizontal, TS.Spacing.sm)
                    .padding(.vertical, TS.Spacing.xs)
                    .background(bugStatusColor(report.status).opacity(0.12))
                    .foregroundStyle(bugStatusColor(report.status))
                    .clipShape(Capsule())

                Spacer()

                if let createdAt = report.createdAt {
                    Text(formattedDate(createdAt))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                }
            }

            // Title
            Text(report.title)
                .font(TS.Font.bodyMedium)
                .foregroundStyle(Color.labelPrimary)

            // Reporter
            Text(report.reporterEmail)
                .font(TS.Font.caption)
                .foregroundStyle(Color.labelTertiary)

            // Description
            if !report.description.isEmpty {
                Text(report.description)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(3)
            }

            // Status action buttons
            Divider()

            HStack(spacing: TS.Spacing.sm) {
                statusActionButton("Nieuw", targetStatus: "new", currentStatus: report.status, reportId: report.id)
                statusActionButton("In behandeling", targetStatus: "in_progress", currentStatus: report.status, reportId: report.id)
                statusActionButton("Opgelost", targetStatus: "resolved", currentStatus: report.status, reportId: report.id)
            }
        }
        .padding(TS.Spacing.md)
        .modernCard()
    }

    private func statusActionButton(_ label: String, targetStatus: String, currentStatus: String, reportId: String) -> some View {
        Button {
            Task {
                do {
                    try await APIService.shared.updateBugReportStatus(id: reportId, status: targetStatus)
                    await loadBugReports()
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
                Text(adminError.type)
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
            if let reporter = adminError.reporterEmail, !reporter.isEmpty {
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
                .disabled(newUserEmail.isEmpty)
            }
        }
        .padding(TS.Spacing.xl)
        .frame(minWidth: 380)
    }

    // MARK: - Create Invitation Sheet

    private var createInvitationSheet: some View {
        VStack(spacing: TS.Spacing.lg) {
            Text("Nieuwe uitnodiging")
                .font(TS.Font.title3Bold)
                .foregroundStyle(Color.labelPrimary)

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("E-mailadres")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                TextField("gebruiker@voorbeeld.nl", text: $newInvitationEmail)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text("Rol")
                    .font(TS.Font.footnoteSemibold)
                    .foregroundStyle(Color.labelSecondary)
                Picker("Rol", selection: $newInvitationRole) {
                    Text("User").tag("user")
                    Text("Admin").tag("admin")
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: TS.Spacing.md) {
                Button("Annuleer") {
                    showCreateInvitationSheet = false
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Verstuur") {
                    Task {
                        do {
                            try await APIService.shared.createInvitation(
                                email: newInvitationEmail,
                                role: newInvitationRole
                            )
                            showCreateInvitationSheet = false
                            await loadInvitations()
                        } catch {
                            errorMessage = "Uitnodiging mislukt: \(error.localizedDescription)"
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newInvitationEmail.isEmpty)
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

    private func bugCategoryLabel(_ category: String) -> String {
        switch category.lowercased() {
        case "bug":     return "Bug"
        case "feature": return "Feature"
        case "general": return "Algemeen"
        default:        return category.capitalized
        }
    }

    private func bugCategoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "bug":     return Color.statusError
        case "feature": return Color.statusSuccess
        case "general": return Color.brandOrange
        default:        return Color.labelTertiary
        }
    }

    private func bugStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "new":         return "Nieuw"
        case "in_progress": return "In behandeling"
        case "resolved":    return "Opgelost"
        default:            return status.capitalized
        }
    }

    private func bugStatusColor(_ status: String) -> Color {
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
        async let bugReportsResult: () = loadBugReports()
        async let errorsResult: () = loadErrors()

        _ = await (statsResult, usersResult, invitationsResult, bugReportsResult, errorsResult)
        isLoading = false
    }

    private func loadStats() async {
        do {
            stats = try await APIService.shared.getAdminStats()
        } catch {
            print("AdminView: stats laden mislukt: \(error.localizedDescription)")
        }
    }

    private func loadUsers() async {
        do {
            users = try await APIService.shared.getAdminUsers()
        } catch {
            print("AdminView: gebruikers laden mislukt: \(error.localizedDescription)")
        }
    }

    private func loadInvitations() async {
        do {
            invitations = try await APIService.shared.getAdminInvitations()
        } catch {
            print("AdminView: uitnodigingen laden mislukt: \(error.localizedDescription)")
        }
    }

    private func loadBugReports() async {
        do {
            bugReports = try await APIService.shared.getAdminBugReports()
        } catch {
            print("AdminView: bug rapporten laden mislukt: \(error.localizedDescription)")
        }
    }

    private func loadErrors() async {
        do {
            errors = try await APIService.shared.getAdminErrors()
        } catch {
            print("AdminView: fouten laden mislukt: \(error.localizedDescription)")
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
    let id: String
    let email: String
    let role: String
    let createdAt: String?
    let usedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case createdAt = "created_at"
        case usedAt = "used_at"
    }
}

struct AdminBugReport: Codable, Identifiable {
    let id: String
    let category: String
    let status: String
    let title: String
    let description: String
    let reporterEmail: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, status, title, description
        case reporterEmail = "reporter_email"
        case createdAt = "created_at"
    }
}

struct AdminError: Codable, Identifiable {
    let id: String
    let type: String
    let endpoint: String?
    let message: String
    let reporterEmail: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, endpoint, message
        case reporterEmail = "reporter_email"
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
