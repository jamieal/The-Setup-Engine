import SwiftUI

struct AppsStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    @State private var searchText = ""
    @State private var searchResults: [AppEntry] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private static let searchAnchor = "search-anchor"

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)

            HStack(alignment: .top, spacing: 24) {
                browseColumn
                selectedColumn
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("Choose your apps")
                .font(.system(size: 28, weight: .bold))
            Text("\(coordinator.appsToInstall.count) to install")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Browse column

    private var browseColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    searchField
                        .id(Self.searchAnchor)

                    if searchText.trimmingCharacters(in: .whitespaces).count >= 2 {
                        searchResultsList
                    } else {
                        categoriesList
                        searchAgainPrompt(proxy: proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: searchText) { scheduleSearch() }
                .onSubmit { Task { await runSearch() } }
            if isSearching {
                ProgressView().controlSize(.small)
            }
            if searchText.isEmpty {
                Text("⌘K")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var searchResultsList: some View {
        LazyVStack(spacing: 6) {
            if !isSearching && searchResults.isEmpty {
                Text("No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(searchResults) { app in
                appRow(app)
            }
        }
    }

    // MARK: - Categories

    /// Renders every category with all its apps. Already-installed apps are shown
    /// greyed out and non-interactive — visible for context, but not in the way.
    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Suggestions.categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .foregroundStyle(.tint)
                        Text(category.name)
                            .font(.callout.weight(.semibold))
                    }
                    .padding(.horizontal, 4)

                    ForEach(category.apps) { app in
                        appRow(app)
                    }
                }
            }
        }
    }

    /// "Don't see your app?" footer that scrolls back to the search field and focuses it.
    private func searchAgainPrompt(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(Self.searchAnchor, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                searchFocused = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Don't see your app? **Search above** ↑")
                Spacer()
                Text("⌘K")
                    .font(.caption)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - App row

    private func appRow(_ app: AppEntry) -> some View {
        let installed = coordinator.isInstalled(app)
        let selected = coordinator.isSelected(app)

        return Button {
            guard !installed else { return }
            withAnimation(.spring(response: 0.25)) {
                coordinator.toggle(app)
            }
        } label: {
            HStack(spacing: 12) {
                CaskIconView(homepageURL: app.homepageURL, caskName: app.caskName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(installed ? .secondary : .primary)
                    HStack(spacing: 5) {
                        if installed {
                            Text("Installed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        } else if let label = app.pricing.shortLabel {
                            let isFreemium = app.pricing == .freemium
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isFreemium ? .blue : .orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (isFreemium ? Color.blue : Color.orange).opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        if let desc = app.desc, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected && !installed ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .opacity(installed ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(installed)
    }

    // MARK: - Selected column

    private var selectedColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To install")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 4)

            // Hide already-installed apps from this list — they're visible in the
            // "Already on your Mac" section in the browse column. Showing them here
            // duplicates info and bloats the sidebar.
            let toInstall = coordinator.appsToInstall

            if toInstall.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(toInstall) { app in
                            HStack(spacing: 10) {
                                CaskIconView(homepageURL: app.homepageURL, caskName: app.caskName)
                                Text(app.displayName)
                                    .font(.callout)
                                Spacer()
                                Button {
                                    withAnimation { coordinator.toggle(app) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .frame(width: 280)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No apps yet")
                .font(.callout.weight(.medium))
            Text("Pick from the categories or search.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func runSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let names = await BrewSearch.searchNames(query: q)
        guard !names.isEmpty else {
            searchResults = []
            return
        }
        searchResults = await BrewSearch.info(for: Array(names.prefix(20)))
    }
}

#Preview {
    AppsStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
