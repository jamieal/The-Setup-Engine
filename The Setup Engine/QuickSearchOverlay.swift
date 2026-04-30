import SwiftUI

/// Spotlight-style search overlay shown via Cmd+K. Adds the chosen cask to the coordinator.
struct QuickSearchOverlay: View {
    @EnvironmentObject var coordinator: SetupCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [AppEntry] = []
    @State private var isSearching: Bool = false
    @State private var highlightIndex: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if !query.isEmpty {
                Divider()
                resultsList
                Divider()
                hintFooter
            }
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.001)) // capture taps
        .onTapGesture { dismiss() }
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFocused)
                .onSubmit { selectHighlighted() }
                .onChange(of: query) { scheduleSearch() }
                .onKeyPress(.upArrow)   { moveHighlight(by: -1); return .handled }
                .onKeyPress(.downArrow) { moveHighlight(by:  1); return .handled }
                .onKeyPress(.escape)    { dismiss(); return .handled }

            if isSearching {
                ProgressView().controlSize(.small)
            }

            Text("⌘K")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            if !isSearching {
                Text("No matches for \"\(query)\"")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.caskName) { idx, app in
                            resultRow(app: app, index: idx)
                                .id(idx)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .onChange(of: highlightIndex) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(highlightIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(app: AppEntry, index: Int) -> some View {
        let isHighlight = index == highlightIndex
        let alreadyAdded = coordinator.isSelected(app)
        let alreadyInstalled = coordinator.isInstalled(app)

        return Button {
            highlightIndex = index
            commit(app)
        } label: {
            HStack(spacing: 12) {
                CaskIconView(homepageURL: app.homepageURL, caskName: app.caskName)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    if let desc = app.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if alreadyInstalled {
                    Label("Already installed", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else if alreadyAdded {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .opacity(isHighlight ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHighlight ? Color.accentColor.opacity(0.18) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var hintFooter: some View {
        HStack(spacing: 16) {
            hintItem("↑↓", "Navigate")
            hintItem("↩",  "Add")
            hintItem("esc", "Close")
            Spacer()
            if coordinator.isInstalled(results.first ?? AppEntry(caskName: "_", displayName: "_")) == false {
                Text("\(coordinator.selectedApps.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(coordinator.selectedApps.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hintItem(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func moveHighlight(by delta: Int) {
        guard !results.isEmpty else { return }
        highlightIndex = max(0, min(results.count - 1, highlightIndex + delta))
    }

    private func selectHighlighted() {
        guard results.indices.contains(highlightIndex) else { return }
        commit(results[highlightIndex])
    }

    private func commit(_ app: AppEntry) {
        if !coordinator.isSelected(app) && !coordinator.isInstalled(app) {
            coordinator.selectedApps.append(app)
        }
        dismiss()
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            highlightIndex = 0
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        isSearching = true
        defer { isSearching = false }

        let names = await BrewSearch.searchNames(query: q)
        guard !names.isEmpty else {
            results = []
            highlightIndex = 0
            return
        }
        results = await BrewSearch.info(for: Array(names.prefix(20)))
        highlightIndex = 0
    }
}

/// Shared brew search helpers — used by AppsStep and the Cmd+K overlay.
enum BrewSearch {
    static func searchNames(query: String) async -> [String] {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "brew search --casks \(query)"]
            p.environment = ShellRunner.brewEnvironment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.contains("==>") }
            } catch {
                return []
            }
        }.value
    }

    static func info(for names: [String]) async -> [AppEntry] {
        await Task.detached {
            let joined = names.joined(separator: " ")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "brew info --json=v2 --cask \(joined)"]
            p.environment = ShellRunner.brewEnvironment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let casks = json["casks"] as? [[String: Any]] {
                    return casks.compactMap { c in
                        guard let token = c["token"] as? String else { return nil }
                        let displayName = (c["name"] as? [String])?.first
                            ?? token.replacingOccurrences(of: "-", with: " ").capitalized
                        return AppEntry(
                            caskName: token,
                            displayName: displayName,
                            homepageURL: c["homepage"] as? String,
                            desc: c["desc"] as? String
                        )
                    }
                }
            } catch {}
            return names.map { name in
                AppEntry(
                    caskName: name,
                    displayName: name.replacingOccurrences(of: "-", with: " ").capitalized
                )
            }
        }.value
    }
}
