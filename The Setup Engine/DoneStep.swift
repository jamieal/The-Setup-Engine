import SwiftUI

/// The finish screen (#16): what changed, the receipt, undo, and the app
/// removing itself — set up once, then gone.
struct DoneStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator
    @State private var animateIn = false
    @State private var confirmUndo = false
    @State private var confirmRemove = false
    @State private var undoing = false
    @State private var removalFailed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.green.opacity(0.25), .mint.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: 120, height: 120)
                    .scaleEffect(animateIn ? 1 : 0.6)
                    .opacity(animateIn ? 1 : 0)

                Image(systemName: "checkmark")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(animateIn ? 1 : 0.4)
                    .opacity(animateIn ? 1 : 0)
            }
            .padding(.bottom, 16)

            Text("Your Mac is ready")
                .font(.system(size: 34, weight: .bold))
                .padding(.bottom, 8)

            Text(summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            changesCard
                .padding(.top, 20)

            if showGatekeeperHint {
                gatekeeperHint
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            finishButtons
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateIn = true
            }
        }
        .confirmationDialog("Undo the changes to your settings?", isPresented: $confirmUndo) {
            Button("Undo Changes", role: .destructive) {
                undoing = true
                Task {
                    await coordinator.undoChanges()
                    undoing = false
                }
            }
        } message: {
            Text("Your Dock, wallpaper and system settings go back to how they were. Installed apps stay.")
        }
        .confirmationDialog("Remove The Setup Engine?", isPresented: $confirmRemove) {
            Button("Remove and Quit", role: .destructive) {
                removalFailed = !SelfRemoval.removeAndQuit()
            }
        } message: {
            Text("It deletes its caches and logs and moves itself to the Trash. Your apps, settings and receipt stay.")
        }
    }

    // MARK: - What changed

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changeLines, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle")
                    .font(.callout)
            }
            ForEach(coordinator.selectedApps.filter { coordinator.failureReasons[$0.caskName] != nil }) { app in
                Label {
                    Text(app.displayName).fontWeight(.semibold) + Text(": " + (coordinator.failureReasons[app.caskName] ?? ""))
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                .font(.callout)
            }

            HStack(spacing: 12) {
                if let receipt = coordinator.receiptURL {
                    Button("Open receipt") { NSWorkspace.shared.open(receipt) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([receipt]) }
                        .buttonStyle(.link)
                }
                Spacer()
                if coordinator.changesUndone {
                    Label("Changes undone", systemImage: "arrow.uturn.backward.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if coordinator.hasUndoableChanges {
                    Button(undoing ? "Undoing…" : "Undo settings changes") { confirmUndo = true }
                        .disabled(undoing)
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: 600, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var changeLines: [String] {
        var lines: [String] = []
        let installed = installedCount
        if installed > 0 { lines.append("\(installed) \(installed == 1 ? "app" : "apps") installed and checked with Apple") }
        let changed = zip(coordinator.settingsBefore, coordinator.settingsAfter).filter { $0 != $1 }.count
        if changed > 0 { lines.append("\(changed) system \(changed == 1 ? "setting" : "settings") changed") }
        lines += coordinator.personalNotes
        if coordinator.installedHomebrew {
            lines.append("Homebrew installed, so your command-line tools keep working")
        }
        return lines
    }

    // MARK: - Finish

    @ViewBuilder
    private var finishButtons: some View {
        VStack(spacing: 10) {
            if SelfRemoval.canRemoveItself && !removalFailed {
                Button {
                    confirmRemove = true
                } label: {
                    Text("Finish and remove The Setup Engine")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                Button("Quit and keep it") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
            } else {
                Button {
                    SelfRemoval.removeTraces()
                    NSApp.terminate(nil)
                } label: {
                    Text("Finish")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)

                Text("Its caches and logs are cleared when you finish. To remove the app itself, drag The Setup Engine to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
    }

    // MARK: - Helpers

    private var installedCount: Int {
        coordinator.selectedApps.filter { coordinator.itemStatuses[$0.caskName] == .succeeded }.count
    }

    /// Apps installed directly were already checked with Apple and open without
    /// a prompt. Homebrew-installed apps can still show macOS's first-open check.
    private var showGatekeeperHint: Bool {
        coordinator.selectedApps.contains {
            $0.kind == .app && coordinator.usesHomebrew($0) && coordinator.itemStatuses[$0.caskName] == .succeeded
        }
    }

    private var gatekeeperHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            Text("When you first open an app installed through Homebrew, macOS may ask \"Are you sure you want to open it?\" That's normal — click Open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: 600, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: String {
        let installed = installedCount
        let failed = coordinator.failedItems.count
        let apps = "\(installed) \(installed == 1 ? "app" : "apps")"
        if failed == 0 {
            return installed == 0
                ? "Your settings are applied. Everything that changed is in your receipt."
                : "We installed \(apps) and set things up your way. Everything that changed is in your receipt."
        }
        return "We installed \(apps) and set things up your way. \(failed) couldn't be installed; the reasons are below."
    }
}

#Preview {
    DoneStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
