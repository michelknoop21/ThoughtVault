// TranscriptsView+iOS.swift
// ThoughtVault
//
// iOS Notulen list, reconstructed from the approved NorthStar
// (docs/design/ios/thoughtvault-ios-notulen-northstar.jpg): search with a
// filter button, the date switch, work in progress and the notulen cards.
// The NorthStar's "Alle / Recent / Favorieten" switch maps onto the existing
// date filter (product decision 2026-09-29: favourites do not exist); month,
// tags, sorting and multi-select live in the filter menu. Badges show the
// first tag, the only per-notule label the app stores.

#if os(iOS)
import SwiftUI

extension TranscriptsView {

    var iosList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                IOSBrandBar()
                    .padding(.top, -10)
                Text("Notulen")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(IOSColor.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 2)
                searchRow
                    .padding(.top, 10)
                IOSSegmented(options: [(DateFilter.all, "Alles", nil),
                                       (.today, "Vandaag", nil),
                                       (.week, "Deze week", nil)],
                             selection: $selectedDateFilter, height: 38)
                    .padding(.top, 12)
                banners
                processingSection
                listSection
                    .padding(.top, 22)
            }
            .padding(.horizontal, IOSMetric.gutter)
            .padding(.bottom, isSelecting ? 90 : 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await loadTranscripts() }
        .iosScreen()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
    }

    // MARK: Search and filters

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(IOSColor.text2)
                TextField("", text: $searchText,
                          prompt: Text("Zoek in notulen\u{2026}").foregroundStyle(IOSColor.text3))
                    .font(.system(size: 15))
                    .foregroundStyle(IOSColor.text)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(IOSColor.text3)
                    }
                    .accessibilityLabel("Zoekopdracht wissen")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IOSColor.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(IOSColor.borderViolet.opacity(0.7), lineWidth: 1))

            filterMenu
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Periode", selection: $selectedDateFilter) {
                ForEach(DateFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            if !availableTags.isEmpty {
                Menu("Tags") {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            if selectedTags.contains(tag) { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                        } label: {
                            if selectedTags.contains(tag) { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                        }
                    }
                    if !selectedTags.isEmpty {
                        Divider()
                        Button("Wis tags") { selectedTags.removeAll() }
                    }
                }
            }
            Divider()
            Button(isSelecting ? "Selecteren stoppen" : "Selecteren", systemImage: "checkmark.circle") {
                isSelecting.toggle()
                selectedIds.removeAll()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(filtersActive ? IOSColor.lavender : IOSColor.text)
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(IOSColor.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(IOSColor.borderViolet.opacity(0.7), lineWidth: 1))
        }
        .accessibilityLabel("Filters")
    }

    private var filtersActive: Bool { !selectedTags.isEmpty || selectedDateFilter == .month }

    // MARK: Banners

    @ViewBuilder
    private var banners: some View {
        if pendingOfflineCount > 0 {
            banner(icon: "icloud.and.arrow.up", tint: IOSColor.warning,
                   text: pendingOfflineCount == 1 ? "1 opname wacht op upload" : "\(pendingOfflineCount) opnames wachten op upload",
                   action: ("Upload nu", { Task { await recordingVM.processQueueOnStartupIfNeeded() } }))
                .padding(.top, 14)
        }
        if let error = loadErrorMessage {
            banner(icon: "exclamationmark.triangle.fill", tint: IOSColor.danger, text: error,
                   action: ("Opnieuw", { Task { await loadTranscripts() } }))
                .padding(.top, 14)
        }
    }

    private func banner(icon: String, tint: Color, text: String, action: (String, () -> Void)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13)).foregroundStyle(IOSColor.text2).lineLimit(2)
            Spacer(minLength: 6)
            Button(action.0, action: action.1)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IOSColor.link)
        }
        .padding(14)
        .iosCard()
    }

    // MARK: Processing

    @ViewBuilder
    private var processingSection: some View {
        if !activeTasks.isEmpty || !errorTasks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                IOSSectionHeader(title: "Wordt verwerkt") {
                    if !activeTasks.isEmpty {
                        Text("\(activeTasks.count) actief").font(.system(size: 13)).foregroundStyle(IOSColor.text2)
                    }
                }
                ForEach(activeTasks) { task in
                    NavigationLink { IOSProcessingView(taskID: task.taskId) } label: { IOSProcessingCard(task: task) }
                        .buttonStyle(.plain)
                }
                ForEach(errorTasks) { task in
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IOSColor.danger)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.filename).font(.system(size: 14, weight: .semibold)).foregroundStyle(IOSColor.text).lineLimit(1)
                            Text(task.errorMessage ?? "Verwerking is mislukt.").font(.system(size: 12)).foregroundStyle(IOSColor.text2).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .iosCard()
                }
            }
            .padding(.top, 20)
        }
    }

    // MARK: List

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            IOSSectionHeader(title: sectionTitle) {
                Menu {
                    Picker("Sorteren", selection: $sortNewest) {
                        Text("Meest recent").tag(true)
                        Text("Oudste eerst").tag(false)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(sortNewest ? "Meest recent" : "Oudste eerst")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(IOSColor.text2)
                }
            }
            let items = filteredTranscripts
            if isLoading && transcripts.isEmpty {
                ProgressView().tint(IOSColor.lavender).frame(maxWidth: .infinity).padding(40)
            } else if transcripts.isEmpty {
                emptyCard(title: "Nog geen notulen",
                          text: "Neem een gesprek op; de notule verschijnt hier zodra hij klaar is.",
                          action: onStartRecording.map { start in ("Start opname", start) })
            } else if items.isEmpty {
                emptyCard(title: "Geen resultaten", text: "Pas je zoekopdracht of filters aan.", action: nil)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { transcript in
                        if isSelecting {
                            Button { toggle(transcript) } label: { card(transcript) }
                                .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: transcript) { card(transcript) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Verwijderen", systemImage: "trash", role: .destructive) {
                                        transcriptToDelete = transcript
                                        showSingleDeleteConfirm = true
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var sectionTitle: String {
        switch selectedDateFilter {
        case .all: return "Alle notulen"
        case .today: return "Vandaag"
        case .week: return "Deze week"
        case .month: return "Deze maand"
        }
    }

    private func emptyCard(title: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(IOSColor.text)
            Text(text).font(.system(size: 13)).foregroundStyle(IOSColor.text2).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSColor.link)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .iosCard()
    }

    private func card(_ transcript: Transcript) -> some View {
        let isNotule = transcript.notuleHtml != nil
        let selected = selectedIds.contains(transcript.id)
        return HStack(alignment: .top, spacing: 16) {
            IOSIconTile(systemName: isNotule ? "doc.text" : "doc.text.fill", tint: isNotule ? .violet : .blue, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 8) {
                    Text(transcript.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(IOSColor.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let tag = transcript.tags.first {
                        Text(tag)
                            .font(.system(size: 12))
                            .foregroundStyle(IOSColor.text)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(IOSColor.control))
                            .overlay(Capsule().strokeBorder(IOSColor.border, lineWidth: 1))
                    }
                }
                Text(IOSFormat.meta(transcript.date, duration: transcript.duration))
                    .font(.system(size: 12.5))
                    .foregroundStyle(IOSColor.text2)
                let preview = HomeView.preview(transcript)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(IOSColor.text2)
                        .lineLimit(2)
                }
            }
            Group {
                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? IOSColor.lavender : IOSColor.text3)
                } else {
                    IOSChevron()
                }
            }
            .padding(.top, 18)
        }
        .padding(12)
        .iosCard(highlighted: selected)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ transcript: Transcript) {
        if selectedIds.contains(transcript.id) { selectedIds.remove(transcript.id) } else { selectedIds.insert(transcript.id) }
    }

    private var selectionBar: some View {
        HStack {
            Button("Stoppen") { isSelecting = false; selectedIds.removeAll() }
                .foregroundStyle(IOSColor.text)
            Spacer()
            Button("Verwijder \(selectedIds.count)", role: .destructive) { showBulkDeleteConfirm = true }
                .foregroundStyle(selectedIds.isEmpty ? IOSColor.text3 : IOSColor.danger)
                .disabled(selectedIds.isEmpty)
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }
}
#endif
