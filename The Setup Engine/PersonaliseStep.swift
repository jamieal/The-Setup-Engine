import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The small things that make a Mac feel like yours (#13, #17): Touch ID for
/// sudo, starting folders, a screenshots folder, the Dock and the default browser.
struct PersonaliseStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator
    @State private var newFolder = ""
    @ObservedObject private var wallpapers = WallpaperCollection.shared

    var body: some View {
        VStack(spacing: 24) {
            StepHero(
                symbol: "person.crop.square",
                title: "Make it yours",
                subtitle: "The small things that make a Mac feel like yours. Nothing changes until you press Begin Setup."
            )
            .padding(.top, 28)

            ScrollView {
                VStack(spacing: 14) {
                    dockCard
                    wallpaperCard
                    foldersCard
                    screenshotsCard
                    browserCard
                    touchIDCard
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 16)
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
        }
        .task { await wallpapers.load() }
        .onAppear {
            // Picks may have changed on the Apps step since the Dock was planned.
            if coordinator.personal.dockLayout != .keep && coordinator.personal.dockLayout != .saved {
                coordinator.refreshDockPlan()
            }
            if let path = coordinator.personal.defaultBrowserPath,
               !coordinator.browserChoices.contains(where: { $0.path == path }) {
                coordinator.personal.defaultBrowserPath = nil
            }
        }
    }

    // MARK: - Touch ID

    private var touchIDCard: some View {
        SettingCard(symbol: "touchid", title: "Touch ID for sudo", description: touchIDDescription) {
            switch coordinator.touchIDStatus {
            case .available:
                Toggle("Use Touch ID", isOn: $coordinator.personal.touchID)
                    .toggleStyle(.switch)
                    .labelsHidden()
            case .alreadyOn:
                Label("Already on", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .noFingerprints:
                VStack(alignment: .trailing, spacing: 6) {
                    Button("Add a fingerprint…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Check again") {
                        coordinator.touchIDStatus = TouchIDStatus.detect()
                        coordinator.personal.touchID = coordinator.touchIDStatus == .available
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            case .noSensor:
                Text("Not available")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var touchIDDescription: String {
        switch coordinator.touchIDStatus {
        case .available:      "Use your fingerprint instead of typing your password for sudo in Terminal."
        case .alreadyOn:      "Your fingerprint already works for sudo in Terminal."
        case .noFingerprints: "Add a fingerprint in System Settings first, then come back and check again."
        case .noSensor:       "This Mac has no Touch ID, or its Touch ID keyboard isn't connected."
        }
    }

    // MARK: - Folders

    private var foldersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbol: "folder.badge.plus", title: "Starting folders",
                       description: "Created in your home folder. Folders that already exist are left alone.")

            FlowLayout(spacing: 8) {
                ForEach($coordinator.personal.folders) { $folder in
                    folderChip($folder)
                }
            }

            HStack(spacing: 8) {
                TextField("Add a folder, e.g. Projects or dev/work", text: $newFolder)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addFolder)
                Button("Add", action: addFolder)
                    .disabled(Personalisation.sanitisedFolder(newFolder).isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func folderChip(_ folder: Binding<Personalisation.Folder>) -> some View {
        HStack(spacing: 6) {
            Button {
                folder.wrappedValue.isOn.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: folder.wrappedValue.isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(folder.wrappedValue.isOn ? Color.accentColor : .secondary)
                    Text("~/" + folder.wrappedValue.path)
                        .font(.callout.monospaced())
                }
            }
            .buttonStyle(.plain)

            if folder.wrappedValue.isCustom {
                Button {
                    coordinator.personal.folders.removeAll { $0.id == folder.wrappedValue.id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.background.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2)))
    }

    private func addFolder() {
        let path = Personalisation.sanitisedFolder(newFolder)
        guard !path.isEmpty else { return }
        if let i = coordinator.personal.folders.firstIndex(where: { $0.path == path }) {
            coordinator.personal.folders[i].isOn = true
        } else {
            coordinator.personal.folders.append(.init(path: path, isOn: true, isCustom: true))
        }
        newFolder = ""
    }

    // MARK: - Screenshots

    private var screenshotsCard: some View {
        SettingCard(
            symbol: "camera.viewfinder",
            title: "Screenshots folder",
            description: coordinator.personal.screenshotsFolder
                ? "Screenshots save to " + (coordinator.personal.screenshotsPath as NSString).abbreviatingWithTildeInPath + " instead of the Desktop."
                : "Screenshots keep saving to the Desktop."
        ) {
            HStack(spacing: 10) {
                TextField("Screenshots", text: $coordinator.personal.screenshotsFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .disabled(!coordinator.personal.screenshotsFolder)
                Toggle("Screenshots folder", isOn: $coordinator.personal.screenshotsFolder)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Dock

    private var dockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbol: "dock.rectangle", title: "Do you want these in your Dock?",
                       description: coordinator.personal.dockLayout.detail)

            Picker("", selection: Binding(
                get: { coordinator.personal.dockLayout },
                set: { coordinator.setDockLayout($0) }
            )) {
                ForEach(DockLayout.allCases.filter { $0 != .saved || coordinator.personal.savedDock != nil }) { layout in
                    Text(layout.label).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if coordinator.personal.dockLayout != .keep {
                dockPreview
                dockList
                Text("Untick anything you don't want, and use the arrows to reorder. Apps that don't install are left out, and your current Dock is saved so it can be put back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dockPreview: some View {
        let items = coordinator.personal.dockItems.filter(\.included)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                DockIcon(item: DockItem(path: "/System/Library/CoreServices/Finder.app", name: "Finder"))
                ForEach(items) { DockIcon(item: $0) }
            }
            .padding(10)
        }
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity)
    }

    private var dockList: some View {
        VStack(spacing: 2) {
            ForEach($coordinator.personal.dockItems) { $item in
                let index = coordinator.personal.dockItems.firstIndex { $0.id == item.id } ?? 0
                HStack(spacing: 10) {
                    Toggle("", isOn: $item.included)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    DockIcon(item: item, size: 20)
                    Text(item.name)
                        .font(.callout)
                        .foregroundStyle(item.included ? .primary : .secondary)
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == coordinator.personal.dockItems.count - 1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard coordinator.personal.dockItems.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            coordinator.personal.dockItems.swapAt(index, target)
        }
    }

    // MARK: - Wallpaper

    private var wallpaperCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbol: "photo.on.rectangle", title: "Wallpaper",
                       description: coordinator.personal.wallpaper == .keep
                           ? "Keep your current wallpaper, or pick a new one."
                           : "Set to \(coordinator.personal.wallpaper.label) on every screen.")

            if !wallpapers.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(wallpapers.photos) { photo in
                            wallpaperThumb(photo)
                        }
                    }
                    .padding(2)
                }
            }

            HStack(spacing: 10) {
                Button("Choose your own photo…", action: chooseOwnPhoto)
                if coordinator.personal.wallpaper != .keep {
                    Button("Keep current wallpaper") { coordinator.personal.wallpaper = .keep }
                        .buttonStyle(.link)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func wallpaperThumb(_ photo: WallpaperPhoto) -> some View {
        let selected = coordinator.personal.wallpaper == .collection(photo)
        return Button {
            coordinator.personal.wallpaper = selected ? .keep : .collection(photo)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: photo.thumb) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                )
                Text(photo.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let credit = photo.credit {
                    Text(credit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 160)
        }
        .buttonStyle(.plain)
    }

    private func chooseOwnPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo for your wallpaper"
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.personal.wallpaper = .file(url)
        }
    }

    // MARK: - Browser

    private var browserCard: some View {
        SettingCard(
            symbol: "safari",
            title: "Default browser",
            description: coordinator.personal.defaultBrowserPath == nil
                ? "Leave your default browser as it is."
                : "macOS will ask you to confirm the change at the end of setup."
        ) {
            Picker("", selection: $coordinator.personal.defaultBrowserPath) {
                Text("Don't change").tag(String?.none)
                Divider()
                ForEach(coordinator.browserChoices) { browser in
                    Text(browser.name).tag(String?.some(browser.path))
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }

    // MARK: - Helpers

    private func cardHeader(symbol: String, title: String, description: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// An app's icon for the Dock preview: the real icon when the app is on disk,
/// otherwise the same remote icon the Apps step shows.
struct DockIcon: View {
    let item: DockItem
    var size: CGFloat = 40

    var body: some View {
        Group {
            if FileManager.default.fileExists(atPath: item.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                CaskIconView(homepageURL: item.homepageURL, caskName: item.token ?? item.name,
                             showSubscriptionBadge: false)
                    .scaleEffect(size / 32)
            }
        }
        .frame(width: size, height: size)
        .help(item.name)
    }
}
